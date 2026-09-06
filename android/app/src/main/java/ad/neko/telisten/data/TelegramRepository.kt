package ad.neko.telisten.data

import android.content.Context
import android.os.Build
import ad.neko.telisten.BuildConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import org.drinkless.tdlib.Client
import org.drinkless.tdlib.TdApi as T
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class TelegramException(val code: Int, message: String) : Exception(message)

class TelegramRepository(private val context: Context, val store: LibraryStore) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val incoming = Channel<T.Object>(Channel.UNLIMITED)
    val auth = MutableStateFlow(AuthState())
    val chats = MutableStateFlow<List<MusicChat>>(emptyList())
    val playlistIds = MutableStateFlow<Set<Long>>(emptySet())
    val progress = MutableStateFlow<Map<Int, Float>>(emptyMap())
    val errors = MutableSharedFlow<String>(extraBufferCapacity = 16)
    val artworkUpdates = MutableSharedFlow<Pair<String, String>>(extraBufferCapacity = 64)
    private val thumbnails = java.util.concurrent.ConcurrentHashMap<Int, String>()
    val updates = MutableSharedFlow<T.Object>(extraBufferCapacity = 64)
    private val allChats = java.util.concurrent.ConcurrentHashMap<Long, MusicChat>()
    @Volatile private var folderId: Int? = null
    @Volatile private var knownFolders: Array<T.ChatFolderInfo> = emptyArray()
    private val client: Client

    init {
        System.loadLibrary("tdjni")
        Client.execute(T.SetLogVerbosityLevel(0))
        client = Client.create({ incoming.trySend(it) }, { auth.value = AuthState("error", it.message ?: "Telegram error") }, null)
        scope.launch {
            for (update in incoming) {
                try {
                    when (update) {
                        is T.UpdateAuthorizationState -> authorization(update.authorizationState)
                        is T.UpdateNewChat -> putChat(update.chat)
                        is T.UpdateMessageSendFailed -> errors.emit("Telegram could not send the message: ${update.error.message}")
                        is T.UpdateChatTitle -> { allChats[update.chatId]?.let { allChats[update.chatId] = it.copy(title = update.title); publishChats() } }
                        is T.UpdateChatFolders -> {
                            knownFolders = update.chatFolders
                            selectPlaylistFolder()
                        }
                        is T.UpdateFile -> {
                            progress.update { it + (update.file.id to if (update.file.local.isDownloadingCompleted) 1f else
                                (update.file.local.downloadedSize.toFloat() / update.file.expectedSize.coerceAtLeast(1)).coerceIn(0f, 1f)) }
                            if (update.file.local.isDownloadingCompleted) thumbnails.remove(update.file.id)?.let { artworkUpdates.emit(it to update.file.local.path) }
                        }
                    }
                    updates.emit(update)
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    auth.value = AuthState("error", e.message ?: "Could not connect")
                }
            }
        }
    }
    suspend fun <R : T.Object> call(request: T.Function<R>): R = withTimeout(60_000) {
        suspendCancellableCoroutine { continuation ->
            client.send(request, { result ->
                if (continuation.isActive) {
                    if (result is T.Error) continuation.resumeWithException(TelegramException(result.code, result.message))
                    else { @Suppress("UNCHECKED_CAST") continuation.resume(result as R) }
                }
            })
        }
    }
    private suspend fun authorization(state: T.AuthorizationState) {
        auth.value = when (state) {
            is T.AuthorizationStateWaitTdlibParameters -> {
                if (BuildConfig.TELEGRAM_API_ID == 0 || BuildConfig.TELEGRAM_API_HASH.length != 32) {
                    AuthState("error", "Add TELEGRAM_API_ID and TELEGRAM_API_HASH to ../.env, then rebuild. You can explore the demo now.")
                } else {
                    call(T.SetTdlibParameters().apply {
                        databaseDirectory = java.io.File(store.root, "td").absolutePath
                        filesDirectory = java.io.File(store.root, "telegram-files").absolutePath
                        databaseEncryptionKey = SessionKeys(context).databaseKey(store.accountId)
                        useFileDatabase = true; useChatInfoDatabase = true; useMessageDatabase = true; useSecretChats = false
                        apiId = BuildConfig.TELEGRAM_API_ID; apiHash = BuildConfig.TELEGRAM_API_HASH
                        systemLanguageCode = java.util.Locale.getDefault().language
                        deviceModel = Build.MODEL; systemVersion = Build.VERSION.RELEASE; applicationVersion = BuildConfig.VERSION_NAME
                    })
                    AuthState()
                }
            }
            is T.AuthorizationStateWaitPhoneNumber -> AuthState("phone", "Use the phone number connected to Telegram.")
            is T.AuthorizationStateWaitCode -> AuthState("code", "Enter the code Telegram sent to ${state.codeInfo.phoneNumber}.")
            is T.AuthorizationStateWaitEmailAddress -> AuthState("email", "Telegram requires a login email address.")
            is T.AuthorizationStateWaitEmailCode -> AuthState("emailCode", "Enter the code sent to ${state.codeInfo.emailAddressPattern}.")
            is T.AuthorizationStateWaitPassword -> AuthState("password", state.passwordHint.ifEmpty { "Your two-step verification password" })
            is T.AuthorizationStateWaitOtherDeviceConfirmation -> AuthState("qr", "Telegram → Settings → Devices → Link Desktop Device", state.link)
            is T.AuthorizationStateReady -> {
                scope.launch { try { loadChats() } catch (e: CancellationException) { throw e } catch (e: Exception) { errors.emit(e.message ?: "Chats could not load") } }
                scope.launch { while (isActive) { runCatching { trimStreamingCache() }; delay(60_000) } }
                AuthState("ready", "Connected")
            }
            is T.AuthorizationStateWaitRegistration -> AuthState("error", "Create your Telegram account in the official app, then sign in here.")
            is T.AuthorizationStateClosed -> AuthState("closed", "Signed out")
            else -> AuthState()
        }
    }
    suspend fun authenticate(value: String) {
        when (auth.value.step) {
            "phone" -> call(T.SetAuthenticationPhoneNumber(value, null))
            "code" -> call(T.CheckAuthenticationCode(value))
            "email" -> call(T.SetAuthenticationEmailAddress(value))
            "emailCode" -> call(T.CheckAuthenticationEmailCode(T.EmailAddressAuthenticationCode(value)))
            "password" -> call(T.CheckAuthenticationPassword(value))
        }
    }
    suspend fun qrLogin() { call(T.RequestQrCodeAuthentication(longArrayOf())) }
    suspend fun logout() { call(T.LogOut()); auth.filter { it.step == "closed" }.first(); SessionKeys(context).remove(store.accountId) }
    suspend fun close() {
        if (auth.value.step != "closed") {
            call(T.Close())
            withTimeout(15_000) { auth.filter { it.step == "closed" }.first() }
        }
        scope.cancel(); incoming.close()
    }
    private fun publishChats() { chats.value = allChats.values.sortedBy { it.title.lowercase() } }
    private fun putChat(chat: T.Chat) {
        if (chat.type is T.ChatTypeSecret) return
        allChats[chat.id] = MusicChat(chat.id, chat.title, (chat.type as? T.ChatTypeSupergroup)?.isChannel == true, chat.videoChat?.groupCallId ?: 0)
        publishChats()
    }
    suspend fun loadChats() {
        for (list in listOf(T.ChatListMain(), T.ChatListArchive())) {
            while (true) {
                try { call(T.LoadChats(list, 100)) }
                catch (e: TelegramException) { if (e.code == 404) break else throw e }
            }
        }
    }
    suspend fun setPlaylistFolderName(name: String) {
        store.playlistFolderName = name
        selectPlaylistFolder()
    }
    private fun selectPlaylistFolder() {
        val name = store.playlistFolderName
        val id = knownFolders.firstOrNull { it.name.text.text == name }?.id
        if (folderId != id) playlistIds.value = emptySet()
        folderId = id
        if (id != null) scope.launch { runCatching { refreshFolder(id, name) } }
    }
    private suspend fun refreshFolder(id: Int, name: String) {
        val folder = call(T.GetChatFolder(id))
        if (folderId != id || store.playlistFolderName != name) return
        playlistIds.value = (folder.pinnedChatIds + folder.includedChatIds).toSet()
        playlistIds.value.forEach { putChat(call(T.GetChat(it))) }
    }
    suspend fun music(chatId: Long? = null, query: String = "", cursor: String = ""): MusicPage {
        val messages: Array<T.Message>
        val next: String
        if (chatId == null) {
            val result = call(T.SearchMessages().apply { this.query = query; offset = cursor; limit = 50; filter = T.SearchMessagesFilterAudio() })
            messages = result.messages; next = result.nextOffset
        } else {
            val result = call(T.SearchChatMessages().apply {
                this.chatId = chatId; this.query = query; fromMessageId = cursor.toLongOrNull() ?: 0
                limit = 50; filter = T.SearchMessagesFilterAudio()
            })
            messages = result.messages; next = result.nextFromMessageId.takeIf { it != 0L }?.toString() ?: ""
        }
        return MusicPage(messages.mapNotNull(::track), next)
    }
    fun track(message: T.Message): Track? {
        val audio = (message.content as? T.MessageAudio)?.audio ?: return null
        val reaction = message.interactionInfo?.reactions?.reactions?.firstOrNull { (it.type as? T.ReactionTypeEmoji)?.emoji == "👍" }
        val identity = audio.audio.remote.uniqueId.ifEmpty { "${message.chatId}:${message.id}" }
        audio.albumCoverThumbnail?.file?.takeIf { !it.local.isDownloadingCompleted }?.let { thumbnail ->
            if (thumbnails.putIfAbsent(thumbnail.id, identity) == null) scope.launch { runCatching { call(T.DownloadFile(thumbnail.id, 1, 0, 0, false)) } }
        }
        return Track(identity, message.chatId, message.id,
            audio.audio.id, audio.audio.remote.id, audio.title.ifEmpty { audio.fileName.substringBeforeLast('.') },
            audio.performer.ifEmpty { "Unknown artist" }, audio.fileName, audio.duration, audio.audio.size,
            audio.albumCoverThumbnail?.file?.local?.path?.takeIf { it.isNotEmpty() }, reaction?.totalCount ?: 0, reaction?.isChosen ?: false)
    }
    suspend fun trimStreamingCache() {
        call(T.OptimizeStorage(store.streamBudget, Int.MAX_VALUE, Int.MAX_VALUE, 60, arrayOf(T.FileTypeAudio(), T.FileTypeDocument(), T.FileTypeThumbnail()), longArrayOf(), longArrayOf(), false, 0))
    }
    suspend fun attachedLyrics(track: Track): Lyrics? {
        val query = track.fileName.substringBeforeLast('.')
        val result = call(T.SearchChatMessages().apply { chatId = track.chatId; this.query = query; limit = 30; filter = T.SearchMessagesFilterDocument() })
        val document = result.messages.mapNotNull { (it.content as? T.MessageDocument)?.document }.firstOrNull {
            it.fileName.endsWith(".lrc", true) && it.fileName.substringBeforeLast('.').equals(query, true) && it.document.size in 1..1_048_576
        } ?: return null
        val file = call(T.DownloadFile(document.document.id, 8, 0, 0, true))
        if (!file.local.isDownloadingCompleted) return null
        val text = withContext(Dispatchers.IO) { java.io.File(file.local.path).readText() }
        return Lyrics("Telegram · ${document.fileName}", LrcParser.parse(text))
    }
    suspend fun resolveFile(track: Track): T.File = call(T.GetRemoteFile(track.remoteId, T.FileTypeAudio()))
    suspend fun download(track: Track): java.io.File {
        require(track.size <= store.downloadBudget) { "This track exceeds the cache limit. Increase it in Settings." }
        val file = resolveFile(track)
        call(T.DownloadFile(file.id, 16, 0, 0, false))
        val completed = withTimeout(30 * 60 * 1000L) {
            var current = call(T.GetFile(file.id))
            while (!current.local.isDownloadingCompleted) {
                delay(300); current = call(T.GetFile(file.id))
                check(current.local.isDownloadingActive || current.local.isDownloadingCompleted) { "Download interrupted; tap Download to retry." }
            }
            current
        }
        check(completed.local.isDownloadingCompleted) { "Download interrupted; tap Download to retry." }
        return withContext(Dispatchers.IO) {
            val target = store.file(track)
            val partial = java.io.File(target.path + ".part")
            java.io.File(completed.local.path).copyTo(partial, overwrite = true)
            check(partial.renameTo(target)) { "Could not save download" }
            store.touch(track); store.prune(track.id)
            target
        }
    }
    suspend fun vote(track: Track): Track {
        if (track.voted) call(T.RemoveMessageReaction(track.chatId, track.messageId, T.ReactionTypeEmoji("👍")))
        else call(T.AddMessageReaction(track.chatId, track.messageId, T.ReactionTypeEmoji("👍"), false, true))
        return track(call(T.GetMessage(track.chatId, track.messageId))) ?: track
    }
    suspend fun createPlaylist(title: String): MusicChat {
        require(title.isNotBlank()) { "Enter a playlist name" }
        val folderName = store.playlistFolderName
        val targetFolderId = folderId
        val chat = call(T.CreateNewSupergroupChat(title.trim(), false, true, "", null, 0, false))
        val existing = targetFolderId?.let { call(T.GetChatFolder(it)) }
        val folder = existing ?: T.ChatFolder().apply {
            name = T.ChatFolderName(T.FormattedText(folderName, emptyArray()), false)
            icon = T.ChatFolderIcon("Music"); pinnedChatIds = longArrayOf(); includedChatIds = longArrayOf(); excludedChatIds = longArrayOf()
        }
        folder.includedChatIds = (folder.includedChatIds + chat.id).distinct().toLongArray()
        val id = targetFolderId
        val resultingId = if (id != null) { call(T.EditChatFolder(id, folder)); id } else call(T.CreateChatFolder(folder)).id
        if (store.playlistFolderName == folderName) {
            folderId = resultingId
            playlistIds.update { it + chat.id }
        }
        putChat(chat)
        return allChats.getValue(chat.id)
    }
    suspend fun save(track: Track, playlist: MusicChat) {
        val result = call(T.ForwardMessages(playlist.id, null, track.chatId, longArrayOf(track.messageId), null, false, false))
        check(result.messages.any { it != null }) { "Telegram did not allow this track to be forwarded." }
    }
    suspend fun rename(chat: MusicChat, title: String) { require(title.isNotBlank()); call(T.SetChatTitle(chat.id, title.trim())) }
    suspend fun deletePlaylist(chat: MusicChat) {
        call(T.DeleteChat(chat.id))
        folderId?.let { id ->
            val folder = call(T.GetChatFolder(id))
            folder.includedChatIds = folder.includedChatIds.filter { it != chat.id }.toLongArray()
            folder.pinnedChatIds = folder.pinnedChatIds.filter { it != chat.id }.toLongArray()
            call(T.EditChatFolder(id, folder))
        }
        playlistIds.update { it - chat.id }; allChats.remove(chat.id); publishChats()
    }
    suspend fun deleteTrack(track: Track) { call(T.DeleteMessages(track.chatId, longArrayOf(track.messageId), true)) }
    suspend fun comments(track: Track): List<T.Message> = call(T.GetMessageThreadHistory(track.chatId, track.messageId, 0, 0, 100)).messages.toList().sortedBy { it.date }
    suspend fun comment(track: Track, text: String) {
        val thread = call(T.GetMessageThread(track.chatId, track.messageId))
        val root = thread.messages.lastOrNull()?.id ?: track.messageId
        call(T.SendMessage().apply {
            chatId = thread.chatId
            topicId = T.MessageTopicThread(thread.messageThreadId)
            replyTo = T.InputMessageReplyToMessage().apply { messageId = root; pollOptionId = "" }
            inputMessageContent = T.InputMessageText().apply { this.text = T.FormattedText(text, emptyArray()) }
        })
    }
    suspend fun botChat(bot: SearchBot): Long = call(T.SearchPublicChat(bot.username.removePrefix("@"))).also(::putChat).id
    suspend fun sendText(chat: Long, text: String) { call(T.SendMessage().apply {
        chatId = chat; inputMessageContent = T.InputMessageText().apply { this.text = T.FormattedText(text, emptyArray()) }
    }) }
    suspend fun history(chat: Long) = call(T.GetChatHistory(chat, 0, 0, 50, false)).messages.toList().reversed()
    suspend fun callback(chat: Long, message: Long, data: ByteArray) { call(T.GetCallbackQueryAnswer(chat, message, T.CallbackQueryPayloadData(data))) }
}
