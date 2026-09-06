package ad.neko.telisten.ui

import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.*
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import ad.neko.telisten.TelistenApplication
import ad.neko.telisten.data.*
import ad.neko.telisten.player.PlaybackService
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.drinkless.tdlib.TdApi as T
import java.util.concurrent.Executor

data class Comment(val id: Long, val author: String, val text: String)

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class AppModel(application: Application) : AndroidViewModel(application) {
    val app = application as TelistenApplication
    val store get() = app.store
    val repository get() = app.repository
    var demo by mutableStateOf(false); private set
    var auth by mutableStateOf(AuthState()); private set
    var chats by mutableStateOf<List<MusicChat>>(emptyList()); private set
    var playlists by mutableStateOf<List<MusicChat>>(emptyList()); private set
    var tracks by mutableStateOf(store.tracks); private set
    var favorites by mutableStateOf(store.favorites); private set
    var savedChats by mutableStateOf(store.savedChats); private set
    var downloads by mutableStateOf(store.tracks.filter(store::downloaded).map { it.id }.toSet()); private set
    var progress by mutableStateOf<Map<Int, Float>>(emptyMap()); private set
    var bots by mutableStateOf(store.bots); private set
    var selectedChat by mutableStateOf<MusicChat?>(null); private set
    var page by mutableStateOf("Library")
    var query by mutableStateOf("")
    var globalSearch by mutableStateOf(true)
    var loading by mutableStateOf(false); private set
    var busy by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null)
    var notice by mutableStateOf<String?>(null)
    var hasMore by mutableStateOf(false); private set
    var queue by mutableStateOf<List<Track>>(emptyList()); private set
    var current by mutableStateOf<Track?>(null); private set
    var playing by mutableStateOf(false); private set
    var buffering by mutableStateOf(false); private set
    var position by mutableLongStateOf(0); private set
    var duration by mutableLongStateOf(0); private set
    var mode by mutableStateOf(runCatching { PlaybackMode.valueOf(store.prefs.getString("playbackMode", "ORDER")!!) }.getOrDefault(PlaybackMode.ORDER)); private set
    var nowPlaying by mutableStateOf(false)
    var lyrics by mutableStateOf<List<Lyrics>>(emptyList()); private set
    var selectedLyrics by mutableIntStateOf(0)
    var lyricsLoading by mutableStateOf(false); private set
    var lyricsError by mutableStateOf<String?>(null); private set
    var comments by mutableStateOf<List<Comment>>(emptyList()); private set
    var commentsLoading by mutableStateOf(false); private set
    var commentError by mutableStateOf<String?>(null); private set
    var botMessages by mutableStateOf<List<T.Message>>(emptyList()); private set
    var botId by mutableStateOf<Long?>(null); private set
    var activeBot by mutableStateOf<SearchBot?>(null); private set
    var accounts by mutableStateOf(app.accounts); private set
    var cacheBytes by mutableLongStateOf(store.usedBytes()); private set
    var cacheLimit by mutableLongStateOf(store.cacheLimit); private set
    var lyricsServer by mutableStateOf(store.lyricsServer); private set
    var playlistFolderName by mutableStateOf(store.playlistFolderName); private set
    var showChats by mutableStateOf(store.prefs.getBoolean("showChats", true))
    private var cursor = ""
    private var searchJob: Job? = null
    private var lyricsJob: Job? = null
    private var botJob: Job? = null
    private var playerJob: Job? = null
    private var controller: MediaController? = null
    private var controllerFuture: com.google.common.util.concurrent.ListenableFuture<MediaController>? = null
    private val accountJobs = mutableListOf<Job>()
    private val downloadJobs = mutableMapOf<String, Job>()

    init { observeAccount(); connectPlayer() }
    private fun observeAccount() {
        accountJobs += viewModelScope.launch { repository.errors.collect { if (!demo) error = it } }
        accountJobs += viewModelScope.launch { repository.artworkUpdates.collect { (id, path) ->
            if (!demo) (tracks + store.tracks).firstOrNull { it.id == id }?.let { replace(it.copy(artwork = path)) }
        } }
        accountJobs += viewModelScope.launch { repository.auth.collect { state ->
            if (!demo) { auth = state; if (state.step == "ready") {
                action { val me = repository.call(T.GetMe()); app.accounts = app.accounts.map { if (it.id == app.activeId) it.copy(name = listOf(me.firstName, me.lastName).filter(String::isNotBlank).joinToString(" ")) else it }; accounts = app.accounts }
                search()
            } }
        } }
        accountJobs += viewModelScope.launch { combine(repository.chats, repository.playlistIds) { all, ids -> all to ids }.collect { (all, ids) ->
            if (!demo) { chats = all; playlists = all.filter { it.id in ids } }
        } }
        accountJobs += viewModelScope.launch { repository.progress.collect { if (!demo) progress = it } }
        accountJobs += viewModelScope.launch { repository.updates.collect { update ->
            if (!demo && update is T.UpdateMessageInteractionInfo) {
                val old = tracks.firstOrNull { it.chatId == update.chatId && it.messageId == update.messageId }
                if (old != null) {
                    val reaction = update.interactionInfo?.reactions?.reactions?.firstOrNull { (it.type as? T.ReactionTypeEmoji)?.emoji == "👍" }
                    replace(old.copy(votes = reaction?.totalCount ?: 0, voted = reaction?.isChosen ?: false))
                }
            }
        } }
    }
    private fun connectPlayer() {
        val future = MediaController.Builder(app, SessionToken(app, ComponentName(app, PlaybackService::class.java))).buildAsync()
        controllerFuture = future
        future.addListener({
            runCatching { future.get() }.onSuccess { player ->
                controller = player
                player.addListener(object : Player.Listener {
                    override fun onEvents(player: Player, events: Player.Events) { syncPlayer() }
                    override fun onPlayerError(error: PlaybackException) { this@AppModel.error = error.cause?.message ?: error.message }
                })
                syncPlayer()
            }.onFailure { error = "Media controls could not connect: ${it.message}" }
        }, Executor { runnable -> android.os.Handler(android.os.Looper.getMainLooper()).post(runnable) })
        playerJob?.cancel(); playerJob = viewModelScope.launch { while (isActive) { syncPlayer(); delay(400) } }
    }
    private fun syncPlayer() {
        val player = controller ?: return
        playing = player.isPlaying; buffering = player.playbackState == Player.STATE_BUFFERING
        position = player.currentPosition.coerceAtLeast(0); duration = player.duration.takeIf { it > 0 } ?: (current?.duration?.times(1000L) ?: 0)
        val next = queue.firstOrNull { it.id == player.currentMediaItem?.mediaId } ?: store.tracks.firstOrNull { it.id == player.currentMediaItem?.mediaId }
        if (next != null && next.id != current?.id) { current = next; loadLyrics(); comments = emptyList() }
    }
    fun action(block: suspend () -> Unit) { viewModelScope.launch { try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.message ?: "Something went wrong. Please try again." } } }
    fun authenticate(value: String) { action { busy = true; try { repository.authenticate(value) } finally { busy = false } } }
    fun qrLogin() { action { repository.qrLogin() } }
    fun select(chat: MusicChat?) { selectedChat = chat; page = "Library"; query = ""; globalSearch = chat == null; search() }
    fun search() {
        searchJob?.cancel()
        if (demo) { tracks = demoTracks().filter { query.isBlank() || "${it.title} ${it.artist}".contains(query, true) }; return }
        searchJob = viewModelScope.launch {
            loading = true; cursor = ""; hasMore = false
            try {
                val result = repository.music(if (globalSearch) null else selectedChat?.id, query)
                tracks = ordered(result.tracks); store.remember(tracks); cursor = result.cursor; hasMore = cursor.isNotEmpty()
            } catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.message } finally { loading = false }
        }
    }
    fun loadMore() { if (!hasMore || loading) return; action {
        loading = true
        try { val result = repository.music(if (globalSearch) null else selectedChat?.id, query, cursor)
            tracks = ordered((tracks + result.tracks).distinctBy { "${it.chatId}:${it.messageId}" }); cursor = result.cursor; hasMore = cursor.isNotEmpty(); store.remember(tracks)
        } finally { loading = false }
    } }
    fun visibleTracks(): List<Track> = when (page) {
        "Favorites" -> (tracks + if (demo) emptyList() else store.tracks).distinctBy { it.id }.filter { it.id in favorites }
        "Downloads" -> (tracks + if (demo) emptyList() else store.tracks).distinctBy { it.id }.filter { it.id in downloads }
        else -> tracks
    }
    fun play(track: Track, list: List<Track> = visibleTracks()) {
        val player = controller ?: run { error = "Audio service is connecting. Please try again."; return }
        queue = list.ifEmpty { listOf(track) }.distinctBy { it.id }.let { if (mode == PlaybackMode.REVERSE) it.reversed() else it }
        if (queue.none { it.id == track.id }) queue = queue + track
        if (!demo) store.remember(queue)
        player.setMediaItems(queue.map { item ->
            val uri = if (demo) Uri.fromFile(demoAudio()) else if (store.downloaded(item)) { store.touch(item); Uri.fromFile(store.file(item)) }
            else Uri.Builder().scheme("telegram").authority("audio").appendQueryParameter("remote", item.remoteId).build()
            MediaItem.Builder().setMediaId(item.id).setUri(uri).setMediaMetadata(MediaMetadata.Builder().setTitle(item.title).setArtist(item.artist).setIsPlayable(true).build()).build()
        }, queue.indexOfFirst { it.id == track.id }, 0)
        player.shuffleModeEnabled = mode == PlaybackMode.SHUFFLE
        player.repeatMode = when (mode) { PlaybackMode.REPEAT_ONE -> Player.REPEAT_MODE_ONE; PlaybackMode.SHUFFLE -> Player.REPEAT_MODE_ALL; else -> Player.REPEAT_MODE_OFF }
        player.prepare(); player.play(); current = track; nowPlaying = true; loadLyrics()
    }
    fun togglePlayback() { controller?.let { if (it.isPlaying) it.pause() else { if (it.playbackState == Player.STATE_IDLE) it.prepare(); if (it.playbackState == Player.STATE_ENDED) it.seekTo(0); it.play() } } }
    fun next() { controller?.let { if (mode == PlaybackMode.REPEAT_ONE) { it.seekTo(0); it.play() } else it.seekToNextMediaItem() } }
    fun previous() { controller?.let { if (it.currentPosition > 5000) it.seekTo(0) else it.seekToPreviousMediaItem() } }
    fun seek(value: Long) { controller?.seekTo(value.coerceIn(0, duration)) }
    fun changeMode(value: PlaybackMode) {
        if ((value == PlaybackMode.REVERSE) != (mode == PlaybackMode.REVERSE)) {
            val player = controller
            if (player != null && queue.isNotEmpty()) {
                val at = player.currentPosition; val id = current?.id; val wasPlaying = player.playWhenReady
                val items = (0 until player.mediaItemCount).map(player::getMediaItemAt).reversed()
                queue = queue.reversed(); player.setMediaItems(items, items.indexOfFirst { it.mediaId == id }.coerceAtLeast(0), at); player.prepare(); player.playWhenReady = wasPlaying
            }
        }
        mode = value; if (!demo) store.prefs.edit().putString("playbackMode", value.name).apply(); controller?.shuffleModeEnabled = value == PlaybackMode.SHUFFLE
        controller?.repeatMode = when (value) { PlaybackMode.REPEAT_ONE -> Player.REPEAT_MODE_ONE; PlaybackMode.SHUFFLE -> Player.REPEAT_MODE_ALL; else -> Player.REPEAT_MODE_OFF }
    }
    private fun ordered(items: List<Track>): List<Track> {
        val chat = selectedChat ?: return items
        val order = store.playlistOrders[chat.id.toString()] ?: return items
        val indices = order.withIndex().associate { it.value to it.index }
        return items.sortedBy { indices[it.id] ?: Int.MAX_VALUE }
    }
    fun movePlaylistTrack(index: Int, delta: Int) {
        val chat = selectedChat ?: return
        if (chat.id !in playlists.map { it.id } || index + delta !in tracks.indices) return
        tracks = tracks.toMutableList().apply { add(index + delta, removeAt(index)) }
        if (!demo) store.playlistOrders = store.playlistOrders + (chat.id.toString() to tracks.map { it.id })
    }
    fun moveBot(index: Int, delta: Int) {
        if (index + delta !in bots.indices) return
        bots = bots.toMutableList().apply { add(index + delta, removeAt(index)) }
        if (!demo) store.bots = bots
    }
    fun selectQueueItem(index: Int) { controller?.let { it.seekTo(index, 0); it.play() } }
    fun moveQueue(index: Int, destination: Int) {
        if (destination !in queue.indices) return
        queue = queue.toMutableList().apply { add(destination, removeAt(index)) }; controller?.moveMediaItem(index, destination)
    }
    fun favorite(track: Track) { favorites = if (track.id in favorites) favorites - track.id else favorites + track.id; if (!demo) { store.remember(listOf(track)); store.favorites = favorites } }
    fun saveChat(chat: MusicChat) { savedChats = if (chat.id.toString() in savedChats) savedChats - chat.id.toString() else savedChats + chat.id.toString(); if (!demo) store.savedChats = savedChats }
    private fun replace(track: Track) { tracks = tracks.map { if (it.id == track.id) track else it }; if (current?.id == track.id) current = track; if (!demo) store.remember(listOf(track)) }
    fun vote(track: Track) { if (demo) { replace(track.copy(voted = !track.voted, votes = (track.votes + if (track.voted) -1 else 1).coerceAtLeast(0))); return }; action { replace(repository.vote(track)) } }
    fun download(track: Track) {
        if (demo) { downloads = downloads + track.id; return }
        if (downloadJobs[track.id]?.isActive == true) return
        downloadJobs[track.id] = viewModelScope.launch {
            try { withContext(Dispatchers.IO) { repository.download(track) }; store.remember(listOf(track)); refreshDownloads() }
            catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.message }
        }
    }
    fun removeDownload(track: Track) { if (!demo) store.file(track).delete(); downloads = downloads - track.id; cacheBytes = store.usedBytes() }
    private fun refreshDownloads() { downloads = store.tracks.filter(store::downloaded).map { it.id }.toSet(); cacheBytes = store.usedBytes() }
    fun downloadAll(chat: MusicChat) { action {
        if (demo) { tracks.forEach(::download); return@action }
        var next = ""
        do { val result = repository.music(chat.id, cursor = next); store.remember(result.tracks); result.tracks.forEach { repository.download(it); refreshDownloads() }; next = result.cursor } while (next.isNotEmpty())
        notice = "Playlist is available offline"
    } }
    fun savePlaylist(track: Track?, chat: MusicChat?, title: String) { action {
        if (demo) { if (chat == null) playlists = playlists + MusicChat(-System.currentTimeMillis(), title, true); notice = "Saved in demo"; return@action }
        busy = true
        try { val target = chat ?: repository.createPlaylist(title); if (track != null) repository.save(track, target); notice = "Saved to ${target.title}" } finally { busy = false }
    } }
    fun renamePlaylist(chat: MusicChat, title: String) { action { if (demo) playlists = playlists.map { if (it.id == chat.id) it.copy(title = title) else it } else repository.rename(chat, title) } }
    fun deletePlaylist(chat: MusicChat) { action { if (demo) playlists = playlists - chat else repository.deletePlaylist(chat); if (selectedChat?.id == chat.id) select(null) } }
    fun deleteTrack(track: Track) { action { if (!demo) repository.deleteTrack(track); tracks = tracks - track } }
    fun loadLyrics(force: Boolean = false) {
        val track = current ?: return; lyricsJob?.cancel(); lyrics = emptyList(); selectedLyrics = 0; lyricsError = null
        if (demo) { lyrics = listOf(Lyrics("Demo lyrics", listOf(LyricLine(0.0, "A little room to breathe"), LyricLine(5.0, "Let the afternoon unfold"), LyricLine(10.0, "Every note finds its way home")))); return }
        lyricsJob = viewModelScope.launch {
            lyricsLoading = true
            try {
                val cached = if (!force) store.readLyrics(track) else null
                val attached = if (cached == null && !force) runCatching { repository.attachedLyrics(track) }.getOrNull() else null
                lyrics = (cached ?: attached)?.let { listOf(it) } ?: LyricsRepository(store).find(track, force)
                if (attached != null) store.saveLyrics(track, attached)
            } catch (e: CancellationException) { throw e } catch (e: Exception) { lyricsError = e.message } finally { lyricsLoading = false }
        }
    }
    fun chooseLyrics(index: Int) { selectedLyrics = index; current?.let { if (!demo) store.saveLyrics(it, lyrics[index]) } }
    fun importLyrics(contents: String) { val track = current ?: return; val value = Lyrics("Attached LRC", LrcParser.parse(contents)); lyrics = listOf(value); selectedLyrics = 0; if (!demo) store.saveLyrics(track, value) }
    fun loadComments() { val track = current ?: return; action {
        commentsLoading = true; commentError = null
        try { comments = if (demo) listOf(Comment(1, "Alex", "This belongs on the evening playlist.")) else repository.comments(track).mapNotNull {
            val text = (it.content as? T.MessageText)?.text?.text ?: return@mapNotNull null
            val author = when (val sender = it.senderId) { is T.MessageSenderUser -> repository.call(T.GetUser(sender.userId)).let { user -> "${user.firstName} ${user.lastName}".trim() }; is T.MessageSenderChat -> repository.call(T.GetChat(sender.chatId)).title; else -> "Telegram" }
            Comment(it.id, author, text)
        } } catch (e: Exception) { if (e is CancellationException) throw e; commentError = e.message } finally { commentsLoading = false }
    } }
    fun sendComment(text: String) { if (text.isBlank()) return; val track = current ?: return; action {
        if (demo) comments = comments + Comment(System.currentTimeMillis(), "You", text) else { repository.comment(track, text); loadComments() }
    } }
    fun saveBot(bot: SearchBot) { require(bot.username.removePrefix("@").matches(Regex("[A-Za-z0-9_]{5,32}"))); bots = bots.filter { it.username != bot.username } + bot; if (!demo) store.bots = bots }
    fun removeBot(bot: SearchBot) { bots = bots - bot; if (!demo) store.bots = bots }
    fun openBot(bot: SearchBot) { activeBot = bot; botMessages = emptyList(); botJob?.cancel(); action {
        if (demo) return@action
        botId = repository.botChat(bot); refreshBot()
        botJob = viewModelScope.launch { while (isActive) { delay(2500); try { refreshBot() } catch (_: TelegramException) { } } }
    } }
    private suspend fun refreshBot() { botId?.let { id -> val result = repository.history(id); if (botId == id) botMessages = result } }
    fun closeBot() { botJob?.cancel(); activeBot = null; botId = null }
    fun botSend(text: String, command: Boolean = true) { action { val id = botId ?: return@action; repository.sendText(id, if (command) activeBot?.command(text) ?: text else text); refreshBot() } }
    fun botCallback(message: Long, data: ByteArray) { action { repository.callback(botId ?: return@action, message, data); refreshBot() } }
    fun setSettings(limit: Long, server: String, folder: String = playlistFolderName) { action {
        val folderName = requireNotNull(PlaylistFolderConfiguration.normalizedName(folder)) { "Enter a folder name of 1–12 characters, without line breaks." }
        require(runCatching { java.net.URI(server).let { it.scheme == "https" && !it.host.isNullOrBlank() && it.userInfo == null } }.getOrDefault(false)) { "Enter a valid HTTPS lyrics server URL" }
        cacheLimit = limit; lyricsServer = server.trimEnd('/')
        playlistFolderName = folderName
        if (!demo) repository.setPlaylistFolderName(folderName)
        if (!demo) { store.cacheLimit = limit; store.lyricsServer = lyricsServer; store.prefs.edit().putBoolean("showChats", showChats).apply(); withContext(Dispatchers.IO) { store.prune(current?.id) }; if (auth.step == "ready") repository.trimStreamingCache(); refreshDownloads() }
        notice = "Settings saved"
    } }
    fun switchAccount(id: String) { action {
        busy = true
        try {
            togetherJob?.cancel(); app.broadcast?.stop()
            if (togetherHost && togetherCall != 0) repository.call(T.EndGroupCall(togetherCall))
            togetherCall = 0; togetherChat = null
            controller?.stop(); controllerFuture?.let(MediaController::releaseFuture); controller = null
            app.stopService(Intent(app, PlaybackService::class.java))
            accountJobs.forEach(Job::cancel); accountJobs.clear(); searchJob?.cancel(); lyricsJob?.cancel(); closeBot(); downloadJobs.values.forEach(Job::cancel)
            withTimeout(5000) { while (app.broadcast != null) delay(20) }
            app.switchAccount(id); demo = false; auth = AuthState(); tracks = store.tracks; favorites = store.favorites; savedChats = store.savedChats
            mode = runCatching { PlaybackMode.valueOf(store.prefs.getString("playbackMode", "ORDER")!!) }.getOrDefault(PlaybackMode.ORDER)
            bots = store.bots; cacheLimit = store.cacheLimit; lyricsServer = store.lyricsServer; playlistFolderName = store.playlistFolderName; selectedChat = null; query = ""; current = null; queue = emptyList(); chats = emptyList(); playlists = emptyList()
            refreshDownloads(); observeAccount(); connectPlayer()
        } finally { busy = false }
    } }
    fun addAccount() { val id = java.util.UUID.randomUUID().toString(); app.accounts = app.accounts + Account(id); accounts = app.accounts; switchAccount(id) }
    fun signOut() { action { if (demo) { demo = false; auth = repository.auth.value; tracks = store.tracks; refreshDownloads(); return@action }
        busy = true
        try { repository.logout(); switchAccount(app.activeId)
        } finally { busy = false }
    } }
    var togetherChat by mutableStateOf<MusicChat?>(null); private set
    var togetherHost by mutableStateOf(false); private set
    var togetherStatus by mutableStateOf("Choose a chat to share the moment."); private set
    var togetherLink by mutableStateOf(""); private set
    var togetherContacts by mutableStateOf<List<Pair<Long, String>>>(emptyList()); private set
    private var togetherCall = 0
    private var togetherJob: Job? = null
    fun startTogether(chat: MusicChat, host: Boolean) { action {
        require(!demo) { "Listen Together needs a signed-in Telegram account." }
        require(togetherChat == null) { "End the current session first." }
        if (host) require(current != null && playing) { "Play a song before starting a broadcast." }
        togetherStatus = "Connecting…"
        try {
            val callId = if (host) repository.call(T.CreateVideoChat(chat.id, currentPresence().encode(), 0, true)).id
                else repository.call(T.GetChat(chat.id)).videoChat.groupCallId.also { require(it != 0) { "There is no active session in this chat." } }
            togetherCall = callId; togetherChat = chat; togetherHost = host
            if (host) {
                val endpoint = repository.call(T.GetVideoChatRtmpUrl(chat.id))
                val broadcaster = app.broadcast ?: error("Audio service is unavailable")
                broadcaster.start(endpoint.url.trimEnd('/') + "/" + endpoint.streamKey)
            }
            togetherLink = repository.call(T.GetVideoChatInviteLink(callId, false)).url
            togetherJob = viewModelScope.launch {
                var lastTitle = ""; var observedAt = android.os.SystemClock.elapsedRealtime()
                while (isActive) {
                    try {
                        if (host) {
                            togetherStatus = app.broadcast?.status?.value ?: "Broadcast stopped"
                            if (togetherStatus !in listOf("Live", "Connecting broadcast…")) break
                            repository.call(T.SetVideoChatTitle(callId, currentPresence().encode()))
                        } else {
                            val call = repository.call(T.GetGroupCall(callId))
                            if (!call.isActive) { togetherStatus = "The host ended this session"; break }
                            if (call.title != lastTitle) { lastTitle = call.title; observedAt = android.os.SystemClock.elapsedRealtime() }
                            val presence = Presence.parse(call.title) ?: error("This call is not sharing Telisten playback metadata.")
                            val elapsed = presence.elapsed + if (presence.playing) (android.os.SystemClock.elapsedRealtime() - observedAt) / 1000 else 0
                            if (current?.title != presence.title && current?.title?.startsWith(presence.title) != true) {
                                val matches = repository.music(query = presence.title).tracks
                                val match = matches.minByOrNull { kotlin.math.abs(it.duration.toLong() - presence.duration) + if (it.artist.equals(presence.artist, true)) 0 else 30 }
                                    ?: error("This song is not available in your Telegram music. You can listen using the Telegram invite link.")
                                require(kotlin.math.abs(match.duration - presence.duration) < 10) { "Could not find the host's song in your music." }
                                play(match, listOf(match)); nowPlaying = false
                            }
                            if (kotlin.math.abs(position / 1000 - elapsed) > 2) seek(elapsed * 1000)
                            controller?.playWhenReady = presence.playing
                            togetherStatus = "In sync with ${chat.title}"
                        }
                    } catch (e: CancellationException) { throw e } catch (e: Exception) { togetherStatus = e.message ?: "Connection interrupted" }
                    delay(5000)
                }
            }
        } catch (e: Exception) {
            app.broadcast?.stop()
            if (host && togetherCall != 0) runCatching { repository.call(T.EndGroupCall(togetherCall)) }
            togetherChat = null; togetherCall = 0; togetherStatus = e.message ?: "Could not join"; throw e
        }
    } }
    private fun currentPresence() = Presence(current?.title ?: "Telisten", current?.artist.orEmpty(), position / 1000, duration / 1000, playing)
    fun stopTogether() { action {
        togetherJob?.cancel(); app.broadcast?.stop()
        if (togetherHost && togetherCall != 0) repository.call(T.EndGroupCall(togetherCall))
        togetherCall = 0; togetherChat = null; togetherLink = ""; togetherStatus = "Session ended"
    } }
    fun loadTogetherContacts() { action {
        togetherContacts = repository.call(T.GetContacts()).userIds.map { id -> val user = repository.call(T.GetUser(id)); id to "${user.firstName} ${user.lastName}".trim() }
    } }
    fun inviteTogether(ids: Set<Long>) { action { repository.call(T.InviteVideoChatParticipants(togetherCall, ids.toLongArray())); notice = "Invited ${ids.size} contacts" } }
    fun enableDemo() {
        if (demo) return
        searchJob?.cancel(); lyricsJob?.cancel(); demo = true; auth = AuthState("ready", "Demo"); tracks = demoTracks()
        chats = listOf(MusicChat(-1, "The listening room", true), MusicChat(-2, "Slow afternoons", true), MusicChat(-3, "Friends & frequencies"))
        playlists = listOf(MusicChat(-4, "Soft focus", true), MusicChat(-5, "After hours", true))
        favorites = setOf("demo-1", "demo-3"); downloads = setOf("demo-2"); hasMore = false
    }
    private fun demoTracks() = listOf("Warm light" to "The Sunday Club", "A slower pace" to "Milo Fields", "Between the trees" to "Hana & June", "Blue hour" to "Northbound", "Little things" to "Mellow Coast", "Stay a while" to "Paper Planes").mapIndexed { index, (title, artist) ->
        Track("demo-$index", -1, index.toLong(), index, "", title, artist, "$title.wav", 30, 0, votes = 12 + index * 7)
    }
    private fun demoAudio(): java.io.File {
        val file = java.io.File(app.cacheDir, "demo-tone.wav")
        if (file.exists()) return file
        val sampleRate = 22050; val count = sampleRate * 30
        java.io.DataOutputStream(file.outputStream()).use { out ->
            fun int(value: Int) { out.writeInt(Integer.reverseBytes(value)) }; fun short(value: Int) { out.writeShort(java.lang.Short.reverseBytes(value.toShort()).toInt()) }
            out.writeBytes("RIFF"); int(36 + count * 2); out.writeBytes("WAVEfmt "); int(16); short(1); short(1); int(sampleRate); int(sampleRate * 2); short(2); short(16); out.writeBytes("data"); int(count * 2)
            repeat(count) { i -> val t = i.toDouble() / sampleRate; val fade = minOf(t, 30 - t, 1.0).coerceAtLeast(0.0); short(((kotlin.math.sin(t * 2 * Math.PI * 220) + kotlin.math.sin(t * 2 * Math.PI * 330)) * 900 * fade).toInt()) }
        }
        return file
    }
    override fun onCleared() { controllerFuture?.let(MediaController::releaseFuture); super.onCleared() }
}
