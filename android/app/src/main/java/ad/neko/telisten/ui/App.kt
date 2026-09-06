@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
package ad.neko.telisten.ui

import android.content.Intent
import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import ad.neko.telisten.data.*
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.drinkless.tdlib.TdApi as T

@Composable fun TelistenApp(model: AppModel) {
    var settings by rememberSaveable { mutableStateOf(false) }
    var playlistTrack by remember { mutableStateOf<Track?>(null) }
    var playlistPicker by remember { mutableStateOf(false) }
    var together by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(model.notice) {
        model.notice?.let { snackbar.showSnackbar(it, withDismissAction = true); model.notice = null }
    }
    BackHandler(model.selectedChat != null && !model.nowPlaying && !settings) { model.select(null) }
    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            if (model.auth.step == "ready" || model.page in listOf("Downloads", "Favorites")) {
                Surface(color = MaterialTheme.colorScheme.surface) {
                    Column(Modifier.navigationBarsPadding()) {
                        model.current?.let { MiniPlayer(model) }
                        NavigationBar(
                            modifier = Modifier.height(64.dp),
                            containerColor = MaterialTheme.colorScheme.surface,
                            tonalElevation = 0.dp,
                            windowInsets = WindowInsets(0, 0, 0, 0),
                        ) {
                            listOf(
                                "Library" to Icons.Rounded.LibraryMusic,
                                "Favorites" to Icons.Rounded.FavoriteBorder,
                                "Downloads" to Icons.Rounded.OfflinePin,
                            ).forEach { (page, icon) ->
                                NavigationBarItem(
                                    selected = model.page == page, onClick = { model.page = page },
                                    icon = { Icon(icon, null, Modifier.size(22.dp)) },
                                    label = { Text(page) },
                                )
                            }
                        }
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            if (model.auth.step != "ready" && model.page !in listOf("Downloads", "Favorites")) {
                Login(model, Modifier.widthIn(max = 480.dp))
            } else {
                Library(model, Modifier.widthIn(max = 840.dp), { settings = true }, {
                    playlistTrack = it; playlistPicker = true
                }, { together = true })
            }
        }
    }
    if (settings) ModalBottomSheet(
        onDismissRequest = { settings = false },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) { Settings(model) }
    if (model.nowPlaying && model.current != null) PlayerSheet(model, {
        playlistTrack = it; playlistPicker = true
    }, { together = true })
    if (playlistPicker) PlaylistDialog(model, playlistTrack) { playlistPicker = false }
    if (model.activeBot != null) BotSheet(model)
    if (together) TogetherSheet(model) { together = false }
    model.error?.let { message ->
        AlertDialog(onDismissRequest = { model.error = null }, title = { Text("Couldn't finish that") },
            text = { Text(message) }, confirmButton = { TextButton({ model.error = null }) { Text("OK") } })
    }
}

@Composable private fun Login(model: AppModel, modifier: Modifier) {
    val uriHandler = LocalUriHandler.current
    var input by rememberSaveable(model.auth.step) { mutableStateOf("") }
    val step = model.auth.step
    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Rounded.GraphicEq, null, tint = MaterialTheme.colorScheme.primary)
            Text("Telisten", style = MaterialTheme.typography.titleLarge)
        }
        Text("Sign in to Telegram", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 12.dp))
        Text("Browse your chats, play music, and save songs offline.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(when (step) {
                    "password" -> "Two-step verification"
                    "code", "emailCode" -> "Verification code"
                    "email" -> "Login email"
                    "qr" -> "Scan with Telegram"
                    else -> "Your account"
                }, style = MaterialTheme.typography.titleMedium)
                Text(model.auth.hint, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (step == "connecting") LoadingIndicator(Modifier.size(32.dp))
                if (step in listOf("phone", "code", "emailCode", "email", "password")) {
                    OutlinedTextField(
                        input, { input = it }, Modifier.fillMaxWidth(),
                        label = { Text(when (step) { "phone" -> "Phone number (+81 …)"; "email" -> "Email address"; "password" -> "Password"; else -> "Verification code" }) },
                        singleLine = true, shape = RoundedCornerShape(12.dp),
                        visualTransformation = if (step == "password") PasswordVisualTransformation() else VisualTransformation.None,
                        keyboardOptions = KeyboardOptions(keyboardType = when (step) { "phone" -> KeyboardType.Phone; "email" -> KeyboardType.Email; "password" -> KeyboardType.Password; else -> KeyboardType.Number }, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { model.authenticate(input) }),
                    )
                    Button({ model.authenticate(input) }, Modifier.fillMaxWidth().height(48.dp), enabled = input.isNotBlank() && !model.busy) { Text("Continue") }
                }
                if (step == "phone") TextButton(model::qrLogin) {
                    Icon(Icons.Rounded.QrCode, null, Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)); Text("Sign in with QR code")
                }
                if (step == "qr") {
                    val bitmap = remember(model.auth.link) {
                        val bits = MultiFormatWriter().encode(model.auth.link, BarcodeFormat.QR_CODE, 480, 480)
                        Bitmap.createBitmap(480, 480, Bitmap.Config.ARGB_8888).apply {
                            for (x in 0 until 480) for (y in 0 until 480) setPixel(x, y, if (bits[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
                        }
                    }
                    Image(bitmap.asImageBitmap(), "Telegram sign-in QR code", Modifier.size(220.dp).align(Alignment.CenterHorizontally))
                    TextButton(model::qrLogin) { Text("Refresh QR code") }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(model::enableDemo) { Text("Explore demo") }
            TextButton({ model.page = "Downloads" }) { Text("Listen offline") }
        }
        Text("Connects directly to Telegram. No Telisten server.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        TextButton({ uriHandler.openUri("https://docs.kitta.co/telisten/") }) { Text("Privacy policy") }
    }
}

@Composable private fun CompactSearch(value: String, onChange: (String) -> Unit, placeholder: String, onSearch: () -> Unit) {
    val focus = LocalFocusManager.current
    fun submit() { focus.clearFocus(); onSearch() }
    Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)) {
        Row(Modifier.heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Search, null, Modifier.padding(start = 12.dp, end = 10.dp).size(20.dp), MaterialTheme.colorScheme.onSurfaceVariant)
            BasicTextField(
                value, onChange, Modifier.weight(1f).heightIn(min = 48.dp).padding(vertical = 12.dp).semantics { contentDescription = "Search library" },
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                singleLine = true, cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit() }),
                decorationBox = { field -> Box { if (value.isEmpty()) Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant); field() } },
            )
            if (value.isNotEmpty()) IconButton({ onChange(""); onSearch() }) { Icon(Icons.Rounded.Close, "Clear search", Modifier.size(20.dp)) }
            IconButton(::submit) { Icon(Icons.AutoMirrored.Rounded.ArrowForward, "Search", Modifier.size(20.dp)) }
        }
    }
}

@Composable private fun Library(model: AppModel, modifier: Modifier, onSettings: () -> Unit, onPlaylist: (Track?) -> Unit, onTogether: () -> Unit) {
    var category by rememberSaveable { mutableStateOf("Songs") }
    var rename by remember { mutableStateOf<MusicChat?>(null) }
    var deleting by remember { mutableStateOf<MusicChat?>(null) }
    var savedOnly by rememberSaveable { mutableStateOf(false) }
    val root = model.page == "Library" && model.selectedChat == null
    val section = if (root) category else "Songs"
    var searchText by rememberSaveable(model.page, section, model.selectedChat?.id) { mutableStateOf(if (model.page == "Library" && section == "Songs") model.query else "") }
    val tracks = model.visibleTracks().filter { searchText.isBlank() || "${it.title} ${it.artist}".contains(searchText, true) }
    LaunchedEffect(model.selectedChat?.id) { if (model.selectedChat != null) category = "Songs" }
    LaunchedEffect(model.showChats) { if (!model.showChats && category == "Chats") category = "Songs" }
    Column(modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = if (model.selectedChat != null && model.page == "Library") 4.dp else 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (model.selectedChat != null && model.page == "Library") IconButton({ model.select(null) }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back to library") }
            Text(if (model.page == "Library") model.selectedChat?.title ?: "Telisten" else model.page, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (model.demo) Text("DEMO", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 8.dp))
            IconButton(onTogether) { Icon(Icons.Rounded.SpatialAudioOff, "Listen together", Modifier.size(22.dp)) }
            IconButton(onSettings) { Icon(Icons.Rounded.Tune, "Settings", Modifier.size(22.dp)) }
        }
        CompactSearch(searchText, {
            searchText = it
            if (section == "Songs" && model.page == "Library") model.query = it
        }, when (section) { "Playlists" -> "Search playlists"; "Chats" -> "Search chats"; else -> "Search songs and artists" }) {
            if (section == "Songs" && model.page == "Library") model.search()
        }
        if (root) {
            val tabs = listOf("Songs", "Playlists") + if (model.showChats) listOf("Chats") else emptyList()
            SecondaryTabRow(tabs.indexOf(category).coerceAtLeast(0), containerColor = Color.Transparent) {
                tabs.forEach { name -> Tab(category == name, { category = name }, text = { Text(name, style = MaterialTheme.typography.labelLarge, maxLines = 1, softWrap = false) }) }
            }
        }
        when (section) {
            "Playlists" -> {
                val playlists = model.playlists.filter { it.title.contains(searchText, true) }
                CompactToolbar("${playlists.size} playlists") { TextButton({ onPlaylist(null) }) { Icon(Icons.Rounded.Add, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("New playlist") } }
                LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) {
                    if (playlists.isEmpty()) item { EmptyState(Icons.AutoMirrored.Rounded.PlaylistAdd, "No playlists", "Create a playlist to collect songs from your chats.") }
                    items(playlists, key = { it.id }) { chat ->
                        var menu by remember { mutableStateOf(false) }
                        CollectionRow(chat, "Private Telegram playlist", { model.select(chat) }) {
                            Box {
                                IconButton({ menu = true }) { Icon(Icons.Rounded.MoreVert, "Options for ${chat.title}") }
                                DropdownMenu(menu, { menu = false }) {
                                    DropdownMenuItem({ Text("Download all") }, { menu = false; model.downloadAll(chat) })
                                    DropdownMenuItem({ Text("Rename") }, { menu = false; rename = chat })
                                    DropdownMenuItem({ Text("Delete playlist") }, { menu = false; deleting = chat })
                                }
                            }
                        }
                    }
                }
            }
            "Chats" -> {
                val chats = model.chats.filter { it.title.contains(searchText, true) && (!savedOnly || it.id.toString() in model.savedChats) }.sortedByDescending { it.id.toString() in model.savedChats }
                CompactToolbar("${chats.size} chats") {
                    FilterChip(savedOnly, { savedOnly = !savedOnly }, label = { Text("Saved") }, leadingIcon = { Icon(Icons.Rounded.BookmarkBorder, null, Modifier.size(16.dp)) })
                }
                LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 12.dp)) {
                    if (chats.isEmpty()) item { EmptyState(Icons.Rounded.Forum, "No chats found", "Try a different name or turn off the saved filter.") }
                    items(chats, key = { it.id }) { chat -> CollectionRow(chat, if (chat.channel) "Channel" else "Chat", { model.select(chat) }) {
                        IconButton({ model.saveChat(chat) }) { Icon(if (chat.id.toString() in model.savedChats) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder, "Save ${chat.title}", tint = MaterialTheme.colorScheme.primary) }
                    } }
                }
            }
            else -> {
                if (model.selectedChat != null && model.page == "Library") Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    FilterChip(model.globalSearch, { model.globalSearch = !model.globalSearch; model.search() }, label = { Text("Search all Telegram") })
                }
                CompactToolbar(if (model.loading) "Loading music…" else "${tracks.size} songs") {
                    if (model.bots.isNotEmpty() && model.page == "Library") {
                        var bots by remember { mutableStateOf(false) }
                        Box {
                            IconButton({ bots = true }) { Icon(Icons.Rounded.SmartToy, "Search with a bot", Modifier.size(20.dp)) }
                            DropdownMenu(bots, { bots = false }) { model.bots.forEach { bot -> DropdownMenuItem({ Text("@${bot.username.removePrefix("@")}") }, { bots = false; model.openBot(bot) }) } }
                        }
                    }
                    IconButton({ model.changeMode(PlaybackMode.SHUFFLE); model.play(tracks.random(), tracks) }, enabled = tracks.isNotEmpty()) { Icon(Icons.Rounded.Shuffle, "Shuffle all", Modifier.size(20.dp)) }
                    FilledTonalButton({ model.changeMode(PlaybackMode.ORDER); model.play(tracks.first(), tracks) }, enabled = tracks.isNotEmpty(), contentPadding = PaddingValues(horizontal = 12.dp)) {
                        Icon(Icons.Rounded.PlayArrow, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("Play")
                    }
                }
                LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) {
                    if (model.loading && tracks.isEmpty()) item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { LoadingIndicator(Modifier.size(36.dp)) } }
                    if (tracks.isEmpty() && !model.loading) item { EmptyState(Icons.Rounded.MusicNote, if (searchText.isNotBlank()) "No matching songs" else "No songs yet", when (model.page) { "Downloads" -> "Download a song from its menu to listen offline."; "Favorites" -> "Tap a song's heart to save it here."; else -> "Search Telegram or choose a chat to find music." }) }
                    itemsIndexed(tracks, key = { _, track -> "${track.chatId}:${track.messageId}" }) { _, track ->
                        TrackRow(model, track, model.tracks.indexOf(track), { model.play(track, tracks) }, { onPlaylist(track) })
                    }
                    if (model.hasMore && model.page == "Library") item { TextButton(model::loadMore, Modifier.fillMaxWidth(), enabled = !model.loading) { Text(if (model.loading) "Loading…" else "Load more") } }
                }
            }
        }
    }
    rename?.let { chat -> NameDialog("Rename playlist", chat.title, { rename = null }) { model.renamePlaylist(chat, it); rename = null } }
    deleting?.let { chat -> AlertDialog(onDismissRequest = { deleting = null }, title = { Text("Delete ${chat.title}?") }, text = { Text("This deletes the playlist channel on Telegram. This cannot be undone.") }, confirmButton = { TextButton({ model.deletePlaylist(chat); deleting = null }) { Text("Delete") } }, dismissButton = { TextButton({ deleting = null }) { Text("Cancel") } }) }
}

@Composable private fun CompactToolbar(title: String, actions: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(start = 16.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        actions()
    }
}

@Composable private fun CollectionRow(chat: MusicChat, subtitle: String, onClick: () -> Unit, action: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable(onClick = onClick).heightIn(min = 64.dp).padding(start = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.size(40.dp)) {
            Box(contentAlignment = Alignment.Center) { Icon(if (chat.channel) Icons.Rounded.LibraryMusic else Icons.Rounded.Forum, null, Modifier.size(20.dp), MaterialTheme.colorScheme.primary) }
        }
        Column(Modifier.weight(1f).padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(chat.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        action()
    }
}

@Composable private fun SectionTitle(title: String, subtitle: String, action: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
            if (subtitle.isNotBlank()) Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        }
        action?.invoke()
    }
}

@Composable private fun EmptyState(icon: ImageVector, title: String, description: String) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 28.dp), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, null, Modifier.size(28.dp), MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable private fun Cover(title: String, modifier: Modifier = Modifier, path: String? = null) {
    Box(modifier.clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
        if (!path.isNullOrEmpty()) AsyncImage(java.io.File(path), null, Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
        else Icon(Icons.Rounded.MusicNote, null, Modifier.fillMaxSize(.45f), MaterialTheme.colorScheme.primary)
    }
}

@Composable private fun TrackRow(model: AppModel, track: Track, index: Int, onClick: () -> Unit, onPlaylist: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    val active = model.current?.id == track.id
    Surface(onClick = onClick, shape = RoundedCornerShape(10.dp), color = if (active) MaterialTheme.colorScheme.primaryContainer else Color.Transparent) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Cover(track.title, Modifier.size(40.dp), track.artwork)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(track.title, style = MaterialTheme.typography.titleMedium, color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (track.id in model.downloads) { Icon(Icons.Rounded.OfflinePin, "Downloaded", Modifier.size(12.dp), MaterialTheme.colorScheme.primary); Spacer(Modifier.width(4.dp)) }
                    Text(track.artist, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                model.progress[track.fileId]?.takeIf { it > 0 && it < 1 }?.let { LinearProgressIndicator({ it }, Modifier.fillMaxWidth().height(2.dp)) }
            }
            Text(timeLabel(track.duration.toLong()), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            IconButton({ model.favorite(track) }) {
                Icon(if (track.id in model.favorites) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, "Favorite ${track.title}", Modifier.size(18.dp), if (track.id in model.favorites) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Box {
                IconButton({ menu = true }) { Icon(Icons.Rounded.MoreVert, "Options for ${track.title}", Modifier.size(20.dp)) }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Save to playlist") }, { menu = false; onPlaylist() }, leadingIcon = { Icon(Icons.AutoMirrored.Rounded.PlaylistAdd, null) })
                    DropdownMenuItem({ Text(if (track.id in model.downloads) "Remove download" else "Download") }, { menu = false; if (track.id in model.downloads) model.removeDownload(track) else model.download(track) })
                    DropdownMenuItem({ Text("${if (track.voted) "Remove" else "Add"} 👍 vote (${track.votes})") }, { menu = false; model.vote(track) })
                    if (model.selectedChat?.id == track.chatId && model.playlists.any { it.id == track.chatId }) {
                        DropdownMenuItem({ Text("Move up") }, { menu = false; model.movePlaylistTrack(index, -1) }, enabled = index > 0)
                        DropdownMenuItem({ Text("Move down") }, { menu = false; model.movePlaylistTrack(index, 1) }, enabled = index < model.tracks.lastIndex)
                    }
                    if (model.playlists.any { it.id == track.chatId }) DropdownMenuItem({ Text("Remove from playlist") }, { menu = false; deleting = true })
                }
            }
        }
    }
    if (deleting) AlertDialog(onDismissRequest = { deleting = false }, title = { Text("Remove this song?") }, text = { Text("The message will be deleted from this Telegram playlist.") }, confirmButton = { TextButton({ model.deleteTrack(track); deleting = false }) { Text("Remove") } }, dismissButton = { TextButton({ deleting = false }) { Text("Cancel") } })
}

@Composable private fun MiniPlayer(model: AppModel) {
    val track = model.current ?: return
    Surface(onClick = { model.nowPlaying = true }, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(12.dp)) {
        Column {
            Row(Modifier.heightIn(min = 56.dp).padding(start = 8.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Cover(track.title, Modifier.size(36.dp), track.artwork)
                Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                    Text(track.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(track.artist, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                IconButton(model::togglePlayback) { Icon(if (model.playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, if (model.playing) "Pause" else "Play") }
                IconButton(model::next) { Icon(Icons.Rounded.SkipNext, "Next") }
            }
            LinearProgressIndicator({ if (model.duration > 0) (model.position.toFloat() / model.duration).coerceIn(0f, 1f) else 0f }, Modifier.fillMaxWidth().height(2.dp), trackColor = Color.Transparent)
        }
    }
}

@Composable private fun PlayerSheet(model: AppModel, onPlaylist: (Track) -> Unit, onTogether: () -> Unit) {
    val track = model.current ?: return
    var tab by rememberSaveable { mutableStateOf("Lyrics") }
    ModalBottomSheet(
        onDismissRequest = { model.nowPlaying = false },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.surface,
        dragHandle = null,
    ) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(.94f).imePadding()) {
            Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton({ model.nowPlaying = false }) { Icon(Icons.Rounded.KeyboardArrowDown, "Minimize player") }
                Text("Now playing", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                IconButton(onTogether) { Icon(Icons.Rounded.SpatialAudioOff, "Listen together") }
            }
            // Only the controls scroll on very short/landscape windows; lyrics and queue remain independently scrollable.
            BoxWithConstraints(Modifier.weight(1f)) {
                val controlsHeight = if (maxHeight < 500.dp) maxHeight * .55f else 330.dp
                if (maxWidth > 600.dp && maxWidth > maxHeight) {
                    Row(Modifier.fillMaxSize()) {
                        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) { PlayerControls(model, onPlaylist) }
                        VerticalDivider()
                        Column(Modifier.weight(1f)) { PlayerDetails(model, tab, { tab = it }) }
                    }
                } else {
                    Column(Modifier.fillMaxSize()) {
                        Column(Modifier.heightIn(max = controlsHeight).verticalScroll(rememberScrollState())) { PlayerControls(model, onPlaylist) }
                        Column(Modifier.weight(1f)) { PlayerDetails(model, tab, { tab = it }) }
                    }
                }
            }
        }
    }
}

@Composable private fun PlayerControls(model: AppModel, onPlaylist: (Track) -> Unit) {
    val track = model.current ?: return
    var modeMenu by remember { mutableStateOf(false) }
    var drag by remember(track.id) { mutableStateOf<Float?>(null) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Cover(track.title, Modifier.size(64.dp), track.artwork)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(track.title, style = MaterialTheme.typography.titleLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(track.artist, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            IconButton({ model.favorite(track) }) { Icon(if (track.id in model.favorites) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, "Toggle favorite", tint = MaterialTheme.colorScheme.primary) }
        }
        Slider(
            value = drag ?: model.position.toFloat(), onValueChange = { drag = it },
            onValueChangeFinished = { drag?.let { model.seek(it.toLong()) }; drag = null },
            valueRange = 0f..model.duration.coerceAtLeast(1).toFloat(),
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(timeLabel((drag?.toLong() ?: model.position) / 1000), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(timeLabel(model.duration / 1000), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
            Box {
                IconButton({ modeMenu = true }) {
                    Icon(when (model.mode) { PlaybackMode.SHUFFLE -> Icons.Rounded.Shuffle; PlaybackMode.REPEAT_ONE -> Icons.Rounded.RepeatOne; PlaybackMode.REVERSE -> Icons.Rounded.SwapVert; else -> Icons.AutoMirrored.Rounded.QueueMusic }, model.mode.label, Modifier.size(22.dp))
                }
                DropdownMenu(modeMenu, { modeMenu = false }) { PlaybackMode.entries.forEach { mode -> DropdownMenuItem({ Text(mode.label) }, { model.changeMode(mode); modeMenu = false }) } }
            }
            IconButton(model::previous) { Icon(Icons.Rounded.SkipPrevious, "Previous", Modifier.size(28.dp)) }
            Button(model::togglePlayback, Modifier.size(width = 72.dp, height = 56.dp), shape = RoundedCornerShape(18.dp), contentPadding = PaddingValues(0.dp)) {
                if (model.buffering) LoadingIndicator(Modifier.size(28.dp), color = MaterialTheme.colorScheme.onPrimary)
                else Icon(if (model.playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, if (model.playing) "Pause" else "Play", Modifier.size(30.dp))
            }
            IconButton(model::next) { Icon(Icons.Rounded.SkipNext, "Next", Modifier.size(28.dp)) }
            IconButton({ if (track.id in model.downloads) model.removeDownload(track) else model.download(track) }) { Icon(if (track.id in model.downloads) Icons.Rounded.OfflinePin else Icons.Rounded.Download, if (track.id in model.downloads) "Remove download" else "Download", Modifier.size(22.dp)) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            FilterChip(track.voted, { model.vote(track) }, label = { Text("${track.votes}") }, leadingIcon = { Icon(Icons.Rounded.ThumbUpOffAlt, "Vote", Modifier.size(16.dp)) })
            AssistChip({ onPlaylist(track) }, label = { Text("Save to playlist") }, leadingIcon = { Icon(Icons.AutoMirrored.Rounded.PlaylistAdd, null, Modifier.size(18.dp)) })
        }
    }
}

@Composable private fun PlayerDetails(model: AppModel, tab: String, selectTab: (String) -> Unit) {
    val tabs = listOf("Lyrics", "Queue", "Comments")
    SecondaryTabRow(tabs.indexOf(tab), containerColor = Color.Transparent) {
        tabs.forEach { label -> Tab(tab == label, { selectTab(label); if (label == "Comments") model.loadComments() }, text = { Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1, softWrap = false) }) }
    }
    when (tab) {
        "Lyrics" -> LyricsPanel(model)
        "Queue" -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp)) {
            itemsIndexed(model.queue, key = { _, track -> track.id }) { index, track ->
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f).clickable { model.selectQueueItem(index) }.padding(vertical = 8.dp)) {
                        Text(track.title, style = MaterialTheme.typography.titleMedium, color = if (track.id == model.current?.id) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(track.artist, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconButton({ model.moveQueue(index, index - 1) }, enabled = index > 0) { Icon(Icons.Rounded.KeyboardArrowUp, "Move ${track.title} up") }
                    IconButton({ model.moveQueue(index, index + 1) }, enabled = index < model.queue.lastIndex) { Icon(Icons.Rounded.KeyboardArrowDown, "Move ${track.title} down") }
                }
            }
        }
        "Comments" -> Column(Modifier.fillMaxSize()) {
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (model.commentsLoading) item { LoadingIndicator(Modifier.size(32.dp)) }
                model.commentError?.let { message -> item { Text(message, color = MaterialTheme.colorScheme.error) } }
                if (model.comments.isEmpty() && !model.commentsLoading && model.commentError == null) item { Text("No comments yet.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                items(model.comments, key = { it.id }) { comment -> Column { Text(comment.author, style = MaterialTheme.typography.labelLarge); Text(comment.text, style = MaterialTheme.typography.bodyMedium) } }
            }
            var text by rememberSaveable(model.current?.id) { mutableStateOf("") }
            Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(text, { text = it }, Modifier.weight(1f), placeholder = { Text("Reply on Telegram") }, shape = RoundedCornerShape(12.dp), maxLines = 3)
                IconButton({ model.sendComment(text); text = "" }, enabled = text.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, "Send comment") }
            }
        }
    }
}

@Composable private fun LyricsPanel(model: AppModel) {
    val context = LocalContext.current
    val import = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) model.action {
            val text = withContext(Dispatchers.IO) { context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() } }
            text?.let(model::importLyrics)
        }
    }
    val lyrics = model.lyrics.getOrNull(model.selectedLyrics)
    val lines = lyrics?.lines.orEmpty()
    val active = lines.indexOfLast { it.seconds != null && it.seconds <= model.position / 1000.0 }
    val scroll = rememberLazyListState()
    LaunchedEffect(model.current?.id, model.selectedLyrics, active) {
        if (active >= 0 && !scroll.isScrollInProgress) scroll.animateScrollToItem(active)
    }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp).heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(lyrics?.source?.removePrefix("https://") ?: "Lyrics", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            TextButton({ model.loadLyrics(true) }) { Text("Find match") }
            IconButton({ import.launch(arrayOf("text/*", "application/octet-stream")) }) { Icon(Icons.Rounded.UploadFile, "Import LRC", Modifier.size(20.dp)) }
        }
        if (model.lyrics.size > 1) LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            itemsIndexed(model.lyrics) { index, match -> FilterChip(model.selectedLyrics == index, { model.chooseLyrics(index) }, label = { Text("${match.title} · ${match.artist}") }) }
        }
        if (model.lyricsLoading) LoadingIndicator(Modifier.padding(16.dp).size(32.dp))
        model.lyricsError?.let { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
        if (lines.isEmpty() && !model.lyricsLoading) EmptyState(Icons.Rounded.Lyrics, "No lyrics found", "Try another match or import an LRC file.")
        LazyColumn(Modifier.weight(1f), state = scroll, contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp)) {
            itemsIndexed(lines) { index, line ->
                Text(line.text.ifEmpty { "♪" }, style = MaterialTheme.typography.titleLarge, color = if (index == active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(if (index == active) MaterialTheme.colorScheme.primaryContainer else Color.Transparent)
                        .clickable(enabled = line.seconds != null) { model.seek((line.seconds!! * 1000).toLong()) }.padding(horizontal = 10.dp, vertical = 10.dp))
            }
        }
    }
}
@Composable private fun Settings(model: AppModel) {
    val uriHandler = LocalUriHandler.current
    var server by rememberSaveable { mutableStateOf(model.lyricsServer) }
    var folderName by rememberSaveable(model.app.activeId) { mutableStateOf(model.playlistFolderName) }
    var limit by rememberSaveable { mutableLongStateOf(model.cacheLimit) }
    var addBot by remember { mutableStateOf(false) }
    var signOut by remember { mutableStateOf(false) }
    LazyColumn(Modifier.fillMaxHeight(.9f), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item { Text("Settings", style = MaterialTheme.typography.titleLarge) }
        item { SectionTitle("Accounts", "") }
        items(model.accounts, key = { it.id }) { account ->
            FilledTonalButton({ model.switchAccount(account.id) }, Modifier.fillMaxWidth(), enabled = !model.busy && account.id != model.app.activeId) { Icon(Icons.Rounded.AccountCircle, null); Spacer(Modifier.width(12.dp)); Text(account.name); if (account.id == model.app.activeId) { Spacer(Modifier.width(8.dp)); Icon(Icons.Rounded.Check, null) } }
        }
        item { TextButton(model::addAccount, enabled = !model.busy) { Icon(Icons.Rounded.Add, null); Text("Add account") } }
        item { SectionTitle("Library", "") }
        item { Row(verticalAlignment = Alignment.CenterVertically) { Text("Show Chats tab", Modifier.weight(1f)); Switch(model.showChats, { model.showChats = it }) } }
        item { OutlinedTextField(folderName, { folderName = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("Playlist folder name") }, isError = PlaylistFolderConfiguration.normalizedName(folderName) == null, supportingText = { Text("1–12 characters. Uses this exact Telegram folder name for this account. Existing folders are not renamed.") }) }
        item { TextButton({ folderName = PlaylistFolderConfiguration.DEFAULT_NAME }) { Text("Use _Playlist default") } }
        item { SectionTitle("Offline storage", "${"%.1f".format(model.cacheBytes / (1024.0 * 1024))} MB used") }
        item { Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf(512L, 1024L, 2048L, 5120L).forEach { mb -> FilterChip(limit == mb * 1024 * 1024, { limit = mb * 1024 * 1024 }, label = { Text(if (mb < 1024) "$mb MB" else "${mb / 1024} GB") }) } } }
        item { Text("Oldest downloaded music is removed when the cache reaches this limit.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        item { SectionTitle("Lyrics", "LRCLIB or your own compatible server") }
        item { OutlinedTextField(server, { server = it }, Modifier.fillMaxWidth(), singleLine = true, shape = RoundedCornerShape(18.dp), label = { Text("HTTPS server URL") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)) }
        item { Text("Song title, artist, and duration are sent to this server. Matched lyrics are saved for offline listening.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        item { Button({ model.setSettings(limit, server, folderName) }, Modifier.fillMaxWidth().height(48.dp), enabled = PlaylistFolderConfiguration.normalizedName(folderName) != null && !model.busy) { Text("Save preferences") } }
        item { SectionTitle("Search bots", "Send searches to bots you choose", action = { IconButton({ addBot = true }) { Icon(Icons.Rounded.Add, "Add bot") } }) }
        itemsIndexed(model.bots) { index, bot -> Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("@${bot.username.removePrefix("@")}"); Text("${bot.prefix}<query>${bot.suffix}", style = MaterialTheme.typography.bodySmall) }; IconButton({ model.moveBot(index, -1) }, enabled = index > 0) { Icon(Icons.Rounded.KeyboardArrowUp, "Move bot up") }; IconButton({ model.removeBot(bot) }) { Icon(Icons.Rounded.DeleteOutline, "Remove bot") } } }
        item { TextButton({ signOut = true }, enabled = !model.busy) { Text(if (model.demo) "Leave demo" else "Sign out of this account", color = MaterialTheme.colorScheme.error) } }
        item { TextButton({ uriHandler.openUri("https://docs.kitta.co/telisten/") }) { Text("Privacy policy & data controls") } }
        item { Text("Telisten for Android · ${ad.neko.telisten.BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    if (addBot) {
        var username by remember { mutableStateOf("") }; var prefix by remember { mutableStateOf("") }; var suffix by remember { mutableStateOf("") }
        AlertDialog(onDismissRequest = { addBot = false }, title = { Text("Add a search bot") }, text = { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(username, { username = it }, label = { Text("@username") }, singleLine = true)
            OutlinedTextField(prefix, { prefix = it }, label = { Text("Before query (optional)") })
            OutlinedTextField(suffix, { suffix = it }, label = { Text("After query (optional)") })
            Text("Searches send real messages to this bot.", style = MaterialTheme.typography.bodySmall)
        } }, confirmButton = { TextButton({ model.saveBot(SearchBot(username, prefix, suffix)); addBot = false }, enabled = username.removePrefix("@").matches(Regex("[A-Za-z0-9_]{5,32}"))) { Text("Add") } }, dismissButton = { TextButton({ addBot = false }) { Text("Cancel") } })
    }
    if (signOut) AlertDialog(onDismissRequest = { signOut = false }, title = { Text(if (model.demo) "Leave demo?" else "Sign out?") }, text = { Text("Your downloaded music remains available on this device.") }, confirmButton = { TextButton({ model.signOut(); signOut = false }) { Text("Continue") } }, dismissButton = { TextButton({ signOut = false }) { Text("Cancel") } })
}
@Composable private fun NameDialog(title: String, initial: String = "", dismiss: () -> Unit, submit: (String) -> Unit) {
    var text by rememberSaveable { mutableStateOf(initial) }
    AlertDialog(onDismissRequest = dismiss, title = { Text(title) }, text = { OutlinedTextField(text, { text = it }, label = { Text("Playlist name") }, singleLine = true, shape = RoundedCornerShape(18.dp)) }, confirmButton = { TextButton({ submit(text.trim()) }, enabled = text.isNotBlank()) { Text("Save") } }, dismissButton = { TextButton(dismiss) { Text("Cancel") } })
}
@Composable private fun PlaylistDialog(model: AppModel, track: Track?, dismiss: () -> Unit) {
    var create by remember { mutableStateOf(track == null) }
    if (create) NameDialog("New playlist", dismiss = dismiss) { model.savePlaylist(track, null, it); dismiss() }
    else AlertDialog(onDismissRequest = dismiss, title = { Text("Save to playlist") }, text = {
        LazyColumn { item { Text(track?.title.orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant) }; items(model.playlists) { chat -> TextButton({ model.savePlaylist(track, chat, ""); dismiss() }, Modifier.fillMaxWidth()) { Text(chat.title) } } }
    }, confirmButton = { TextButton({ create = true }) { Text("New playlist") } }, dismissButton = { TextButton(dismiss) { Text("Cancel") } })
}
@Composable private fun BotSheet(model: AppModel) {
    val handler = LocalUriHandler.current
    ModalBottomSheet(onDismissRequest = model::closeBot, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(.88f).padding(horizontal = 24.dp)) {
            Text("@${model.activeBot?.username?.removePrefix("@")}", style = MaterialTheme.typography.headlineMedium)
            Text("Messages are sent through your Telegram account.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 8.dp))
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(model.botMessages, key = { it.id }) { message ->
                    Surface(shape = RoundedCornerShape(20.dp), color = if (message.isOutgoing) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh) {
                        Column(Modifier.fillMaxWidth().padding(16.dp)) {
                            val track = model.repository.track(message)
                            val text = (message.content as? T.MessageText)?.text?.text ?: (message.content as? T.MessageAudio)?.caption?.text.orEmpty()
                            if (text.isNotBlank()) Text(text)
                            if (track != null) FilledTonalButton({ model.play(track, listOf(track)) }) { Icon(Icons.Rounded.PlayArrow, null); Text(track.title) }
                            (message.replyMarkup as? T.ReplyMarkupInlineKeyboard)?.rows?.forEach { row ->
                                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) { row.forEach { button ->
                                    OutlinedButton({ when (val type = button.type) {
                                        is T.InlineKeyboardButtonTypeCallback -> model.botCallback(message.id, type.data)
                                        is T.InlineKeyboardButtonTypeUrl -> { val uri = android.net.Uri.parse(type.url); if (uri.scheme in listOf("http", "https", "tg")) runCatching { handler.openUri(type.url) }.onFailure { model.error = "No app can open this link" } }
                                        else -> model.notice = "Open this button in Telegram"
                                    } }) { Text(button.text) }
                                } }
                            }
                            (message.replyMarkup as? T.ReplyMarkupShowKeyboard)?.rows?.forEach { row -> Row(Modifier.horizontalScroll(rememberScrollState())) { row.forEach { button -> TextButton({ model.botSend(button.text, false) }) { Text(button.text) } } } }
                        }
                    }
                }
            }
            var query by rememberSaveable { mutableStateOf("") }
            Row(Modifier.padding(vertical = 14.dp).imePadding(), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(query, { query = it }, Modifier.weight(1f), label = { Text("Search for music") }, shape = RoundedCornerShape(22.dp), singleLine = true)
                IconButton({ model.botSend(query); query = "" }, enabled = query.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, "Send search") }
            }
        }
    }
}

@Composable private fun TogetherSheet(model: AppModel, dismiss: () -> Unit) {
    val context = LocalContext.current
    var invite by remember { mutableStateOf(false) }
    var chosen by remember { mutableStateOf<Set<Long>>(emptySet()) }
    ModalBottomSheet(onDismissRequest = dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        LazyColumn(Modifier.fillMaxHeight(.9f), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item { Text("Listen together", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp)); Text(model.togetherStatus, Modifier.padding(top = 10.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (model.togetherChat != null) {
                item { Text(model.togetherChat!!.title, style = MaterialTheme.typography.titleLarge) }
                if (model.togetherLink.isNotBlank()) item { Button({ context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, model.togetherLink), "Share listening session")) }, Modifier.fillMaxWidth()) { Icon(Icons.Rounded.Share, null); Spacer(Modifier.width(8.dp)); Text("Share invite link") } }
                if (model.togetherHost) item { OutlinedButton({ invite = !invite; if (invite) model.loadTogetherContacts() }, Modifier.fillMaxWidth()) { Text("Invite contacts") } }
                if (invite) {
                    items(model.togetherContacts, key = { it.first }) { (id, name) -> Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(id in chosen, { chosen = if (id in chosen) chosen - id else chosen + id }); Text(name) } }
                    item { Button({ model.inviteTogether(chosen); invite = false }, enabled = chosen.isNotEmpty()) { Text("Invite ${chosen.size} contacts") } }
                }
                item { TextButton(model::stopTogether) { Text(if (model.togetherHost) "End session for everyone" else "Leave session") } }
            } else {
                item { Text("Host in a chat you manage, or join a Telisten session. Hosts broadcast app audio to Telegram. Telisten listeners sync matching songs from their own library.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                items(model.chats, key = { it.id }) { chat ->
                    Surface(color = MaterialTheme.colorScheme.surfaceContainerHigh, shape = RoundedCornerShape(22.dp)) { Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Text(chat.title, style = MaterialTheme.typography.titleMedium)
                        Row { TextButton({ model.startTogether(chat, true) }) { Text("Host here") }; TextButton({ model.startTogether(chat, false) }) { Text("Join session") } }
                    } }
                }
            }
        }
    }
}
