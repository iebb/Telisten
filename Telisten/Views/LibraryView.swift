import SwiftUI

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #if DEBUG
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("--demo-settings")
    #else
    @State private var showSettings = false
    #endif
    @State private var showSettingsAfterPlayerDismissal = false
    @State private var showDeletePlaylistConfirmation = false
    @State private var isEditingPlaylist = false
    @State private var playlistTitleDraft = ""
    @FocusState private var playlistTitleFocused: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var nowPlayingDetent: PresentationDetent = .medium
    #elseif os(macOS)
    @State private var showsDesktopLyrics = false
    #endif

    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
            } detail: {
                #if os(macOS)
                if showsDesktopLyrics, model.player.track != nil {
                    DesktopLyricsView(model: model)
                } else {
                    trackBrowser
                }
                #else
                trackBrowser
                #endif
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.player.track != nil, !model.showNowPlaying {
                    #if os(macOS)
                    PlayerBar(
                        model: model,
                        showsLyrics: $showsDesktopLyrics,
                        bottomSafeArea: geometry.safeAreaInsets.bottom
                    )
                    #else
                    PlayerBar(model: model, bottomSafeArea: geometry.safeAreaInsets.bottom)
                    #endif
                }
            }
            #if os(iOS)
            .sheet(isPresented: compactNowPlayingPresentation, onDismiss: presentPendingSettings) {
                NowPlayingView(model: model, presentationDetent: $nowPlayingDetent)
                    .presentationDetents([.medium, .large], selection: $nowPlayingDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .sheet(isPresented: compactSettingsPresentation) {
                SettingsView(model: model)
            }
            .inspector(isPresented: regularInspectorPresentation) {
                regularWidthInspector
                    .inspectorColumnWidth(min: 380, ideal: 440, max: 520)
            }
            #else
            .sheet(isPresented: $model.showNowPlaying, onDismiss: presentPendingSettings) {
                NowPlayingView(model: model)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
            }
            #endif
            .sheet(isPresented: $model.showPlaylistSheet) {
                if let track = model.playlistTrack {
                    PlaylistSheet(model: model, track: track)
                }
            }
            .sheet(isPresented: $model.showListenTogetherSheet) {
                ListenTogetherView(model: model)
            }
            .alert(
                "Delete playlist?",
                isPresented: $showDeletePlaylistConfirmation,
                presenting: selectedPlaylist
            ) { playlist in
                Button("Delete Playlist", role: .destructive) {
                    Task {
                        if await model.deletePlaylist(playlist) {
                            withAnimation { columnVisibility = .all }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { playlist in
                Text("This permanently deletes \(playlist.title) from Telegram. This cannot be undone.")
            }
            #if os(iOS)
            .onChange(of: model.showNowPlaying) { _, isPresented in
                guard isPresented else { return }
                if horizontalSizeClass == .regular {
                    showSettings = false
                } else {
                    nowPlayingDetent = .medium
                }
            }
            #endif
        }
    }

    private func openSettings() {
        guard model.showNowPlaying else {
            showSettings = true
            return
        }

        #if os(iOS)
        if horizontalSizeClass == .regular {
            model.showNowPlaying = false
            showSettings = true
            return
        }
        #endif

        showSettingsAfterPlayerDismissal = true
        model.showNowPlaying = false
    }

    private func presentPendingSettings() {
        guard showSettingsAfterPlayerDismissal else { return }
        showSettingsAfterPlayerDismissal = false
        showSettings = true
    }

    #if os(iOS)
    private var compactNowPlayingPresentation: Binding<Bool> {
        Binding(
            get: { horizontalSizeClass != .regular && model.showNowPlaying },
            set: { isPresented in
                guard !isPresented, horizontalSizeClass != .regular else { return }
                model.showNowPlaying = false
            }
        )
    }

    private var compactSettingsPresentation: Binding<Bool> {
        Binding(
            get: { horizontalSizeClass != .regular && showSettings },
            set: { isPresented in
                guard !isPresented, horizontalSizeClass != .regular else { return }
                showSettings = false
            }
        )
    }

    private var regularInspectorPresentation: Binding<Bool> {
        Binding(
            get: {
                horizontalSizeClass == .regular && (showSettings || model.showNowPlaying)
            },
            set: { isPresented in
                guard !isPresented, horizontalSizeClass == .regular else { return }
                showSettings = false
                model.showNowPlaying = false
            }
        )
    }

    @ViewBuilder
    private var regularWidthInspector: some View {
        if showSettings {
            SettingsView(model: model)
        } else {
            NowPlayingView(
                model: model,
                presentationDetent: .constant(.large),
                showsCloseButton: true
            )
        }
    }
    #endif

    private var sidebar: some View {
        List(selection: $model.selected) {
            Section("Library") {
                Label("Search all music", systemImage: "magnifyingglass.circle.fill")
                    .tag(SidebarSelection.globalSearch)
                Label("Favorites", systemImage: "heart.fill")
                    .tag(SidebarSelection.favorites)
                Label("Downloads", systemImage: "arrow.down.circle.fill")
                    .tag(SidebarSelection.downloads)
            }
            if !model.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(model.playlists) { playlist in
                        HStack(spacing: 9) {
                            ChatAvatar(model: model, chat: playlist, size: 26, fallbackSymbol: "music.note.list")
                            Text(playlist.title)
                                .lineLimit(1)
                        }
                        .tag(SidebarSelection.chat(playlist.id))
                    }
                }
            }
            if model.showChats {
                Section("Music Sources") {
                    ForEach(nonPlaylistChats) { chat in
                        HStack(spacing: 9) {
                            ChatAvatar(model: model, chat: chat, size: 26)
                            Text(chat.title)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if let count = model.chatMusicCounts[chat.id] {
                                Text(musicCountLabel(count))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .minimumScaleFactor(0.62)
                                    .lineLimit(1)
                                    .frame(width: 27, height: 27)
                                    .background(Color.secondary.opacity(0.12), in: Circle())
                                    .accessibilityLabel("\(count) music tracks")
                            }
                            if chat.isPinned == true {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                    .accessibilityLabel("Pinned music source")
                            }
                        }
                        .tag(SidebarSelection.chat(chat.id))
                    }
                    if model.isIndexingChats {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Finding music sources…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if nonPlaylistChats.isEmpty {
                        Text("No music sources found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) { accountMenu }
            #else
            ToolbarItem(placement: .navigation) { accountMenu }
            #endif
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button("Listen Together", systemImage: "dot.radiowaves.left.and.right") {
                        model.showListenTogetherSheet = true
                    }
                    Button("Settings", systemImage: "gearshape", action: openSettings)
                }
            }
        }
        .onChange(of: model.selected) { _, value in
            Task { await model.select(value) }
        }
    }

    private var accountMenu: some View {
        Menu {
            ForEach(model.accounts) { account in
                Button {
                    Task { await model.switchAccount(to: account) }
                } label: {
                    Label(
                        account.displayName,
                        systemImage: account.id == model.activeAccountID
                            ? "checkmark.circle.fill"
                            : "person.crop.circle"
                    )
                }
                .disabled(account.id == model.activeAccountID)
            }
            if !model.accounts.isEmpty { Divider() }
            Button("Add Account", systemImage: "person.badge.plus") {
                Task { await model.addAccount() }
            }
        } label: {
            HStack(spacing: 6) {
                if let account = model.activeAccount {
                    AccountAvatar(model: model, account: account, size: 28)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }
                #if os(iOS)
                if horizontalSizeClass != .regular {
                    Text(model.activeAccount?.displayName ?? "Account")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                #else
                Text(model.activeAccount?.displayName ?? "Account")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .accessibilityLabel("Telegram account")
    }

    private var nonPlaylistChats: [MusicChat] {
        let playlistIDs = Set(model.playlists.map(\.id))
        return model.chats.filter { !playlistIDs.contains($0.id) }
    }

    private func musicCountLabel(_ count: Int) -> String {
        count > 999 ? "999+" : String(count)
    }

    private var trackBrowser: some View {
        VStack(spacing: 0) {
            Group {
                if model.isLoading && model.tracks.isEmpty {
                    ProgressView("Finding music…")
                } else if model.tracks.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySymbol,
                        description: Text(emptyDescription)
                    )
                } else {
                    List {
                        ForEach(model.tracks) { track in
                            TrackRow(model: model, track: track)
                                .moveDisabled(selectedPlaylist == nil)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if let playlist = selectedPlaylist {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            Task { await model.delete(track, from: playlist) }
                                        }
                                        .disabled(model.deletingPlaylistTrackIDs.contains(track.id))
                                    }
                                }
                        }
                        .onMove { source, destination in
                            model.moveTracks(from: source, to: destination)
                        }
                        if model.hasMoreTracks {
                            HStack {
                                Spacer()
                                if model.isLoadingMore {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Spacer()
                            }
                            .frame(height: 28)
                            .contentShape(Rectangle())
                            .onAppear {
                                Task { await model.loadMoreTracks() }
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 54)
                    #if os(iOS)
                    .environment(
                        \.editMode,
                        Binding(
                            get: { isEditingPlaylist ? .active : .inactive },
                            set: { isEditingPlaylist = $0.isEditing }
                        )
                    )
                    #endif
                }
            }
        }
        .navigationTitle(isEditingPlaylist && selectedPlaylist != nil ? "" : browserTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(usesCompactBackButton)
        .simultaneousGesture(chatDetailBackGesture)
        #endif
        #if os(iOS)
        .searchable(
            text: $model.searchText,
            placement: .navigationBarDrawer(displayMode: model.isGlobalSearch ? .always : .automatic),
            prompt: model.isGlobalSearch ? "Song, artist, or album" : "Search music here"
        )
        #else
        .searchable(
            text: $model.searchText,
            prompt: model.isGlobalSearch ? "Song, artist, or album" : "Search music here"
        )
        #endif
        .onSubmit(of: .search) { Task { await model.search() } }
        .onChange(of: model.selectedChat?.id) { _, _ in
            isEditingPlaylist = false
            playlistTitleDraft = selectedPlaylist?.title ?? ""
        }
        .onChange(of: isEditingPlaylist) { wasEditing, isEditing in
            if isEditing, let playlist = selectedPlaylist {
                playlistTitleDraft = playlist.title
            } else if wasEditing {
                commitPlaylistTitle()
                playlistTitleFocused = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let playlist = selectedPlaylist, isEditingPlaylist {
                    HStack(spacing: 7) {
                        TextField("Playlist name", text: $playlistTitleDraft)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .submitLabel(.done)
                            .focused($playlistTitleFocused)
                            .onSubmit {
                                commitPlaylistTitle()
                                playlistTitleFocused = false
                            }
                            .accessibilityLabel("Playlist title")
                        if model.renamingPlaylistIDs.contains(playlist.id) {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(width: 180)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.28))
                            .frame(height: 1)
                    }
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                if usesCompactBackButton {
                    Button(action: returnToLibrary) {
                        Label("Library", systemImage: "chevron.left")
                    }
                }
            }
            #endif
            ToolbarItemGroup(placement: .primaryAction) {
                if let playlist = selectedPlaylist {
                    Button(isEditingPlaylist ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEditingPlaylist.toggle()
                        }
                    }
                    if !isEditingPlaylist {
                        Menu("Playlist actions", systemImage: "ellipsis.circle") {
                            Button("Refresh", systemImage: "arrow.clockwise") {
                                Task { await model.search() }
                            }
                            Divider()
                            Text("Track order is saved on this device")
                            if playlist.kind == .channel {
                                Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                                    showDeletePlaylistConfirmation = true
                                }
                            }
                        }
                        .disabled(model.isDeletingPlaylist)
                    }
                } else if !model.isGlobalSearch {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.search() }
                    }
                }
            }
        }
    }

    private var selectedPlaylist: MusicChat? {
        guard let chat = model.selectedChat else { return nil }
        return model.playlists.first { $0.id == chat.id }
    }

    private func commitPlaylistTitle() {
        guard let playlist = selectedPlaylist else { return }
        let title = playlistTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != playlist.title else {
            playlistTitleDraft = playlist.title
            return
        }
        Task {
            if await model.renamePlaylist(playlist, to: title) {
                playlistTitleDraft = title
            }
        }
    }

    #if os(iOS)
    private var usesCompactBackButton: Bool {
        horizontalSizeClass == .compact && model.selected != nil
    }

    private var canSwipeBackFromChat: Bool {
        guard horizontalSizeClass == .compact else { return false }
        if case .chat = model.selected { return true }
        return false
    }

    private var chatDetailBackGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onEnded { value in
                guard canSwipeBackFromChat,
                      value.startLocation.x <= 28,
                      value.translation.width > 64,
                      value.translation.width > abs(value.translation.height) * 1.25 else { return }
                returnToLibrary()
            }
    }

    private func returnToLibrary() {
        if isEditingPlaylist {
            isEditingPlaylist = false
        }
        withAnimation(.easeOut(duration: 0.2)) {
            model.selected = nil
            columnVisibility = .all
        }
    }
    #endif

    private var browserTitle: String {
        return switch model.selected {
        case .globalSearch: "Search All Music"
        case .favorites: "Favorites"
        case .downloads: "Downloads"
        case .chat: model.selectedChat?.title ?? "Music"
        case nil: "Music"
        }
    }

    private var emptyTitle: String {
        switch model.selected {
        case .globalSearch: "Search all music"
        case .favorites: "No favorites yet"
        case .downloads: "Nothing downloaded"
        case .chat: "No music found"
        case nil: "Choose music"
        }
    }

    private var emptySymbol: String {
        switch model.selected {
        case .globalSearch: "magnifyingglass.circle"
        case .favorites: "heart"
        case .downloads: "arrow.down.circle"
        default: "music.note.list"
        }
    }

    private var emptyDescription: String {
        switch model.selected {
        case .globalSearch: "Find songs, artists, or albums across your Telegram music."
        case .favorites: "Tap the heart beside a track to keep it here."
        case .downloads: "Downloaded music remains available offline."
        case .chat: "Try another search or choose a different music source."
        case nil: "Pick a playlist, favorite, download, or music source from the sidebar."
        }
    }
}

private struct TrackRow: View {
    @Bindable var model: AppModel
    let track: Track

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TrackArtwork(model: model, track: track, size: 44)
                    .overlay(alignment: .center) {
                        if isCurrent && model.player.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else if isCurrent && model.player.isPlaying {
                            Image(systemName: "waveform")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if model.cachedIDs.contains(track.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                                .background(.background, in: Circle())
                                .offset(x: 3, y: 3)
                                .accessibilityLabel("Downloaded")
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.displayTitle)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(isCurrent ? Color.telistenAccent : .primary)
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 2)
                downloadProgress
                favoriteButton
                moreMenu
            }
            .padding(.vertical, 6)

            Divider()
                .padding(.leading, 54)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.play(track) }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 8))
        .listRowSeparator(.hidden)
        .contextMenu {
            Button("Play", systemImage: "play.fill") { model.play(track) }
            Button("Add to playlist", systemImage: "text.badge.plus") { model.openPlaylistPicker(for: track) }
            if model.cachedIDs.contains(track.id) {
                Button("Remove download", systemImage: "trash", role: .destructive) { model.removeDownload(track) }
            } else {
                Button("Download", systemImage: "arrow.down.circle") { model.cacheTrack(track) }
            }
        }
    }

    private var favoriteButton: some View {
        Button {
            model.toggleFavorite(track)
        } label: {
            Image(systemName: model.favorites.contains(track.id) ? "heart.fill" : "heart")
                .font(.callout)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.favorites.contains(track.id) ? Color.telistenAccent : .secondary)
        .accessibilityLabel(model.favorites.contains(track.id) ? "Unfavorite" : "Favorite")
    }

    @ViewBuilder private var downloadProgress: some View {
        let status = model.downloads[track.id] ?? .none
        if status.progress > 0, !status.isCached {
            ProgressView(value: status.progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(width: 24)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Add to playlist", systemImage: "text.badge.plus") {
                model.openPlaylistPicker(for: track)
            }
            if model.cachedIDs.contains(track.id) {
                Button("Remove download", systemImage: "trash", role: .destructive) {
                    model.removeDownload(track)
                }
            } else {
                Button("Download", systemImage: "arrow.down.circle") {
                    model.cacheTrack(track)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.callout)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("More actions for \(track.displayTitle)")
    }

    private var metadata: String {
        track.duration > 0
            ? "\(track.displayArtist)  •  \(DisplayFormat.duration(track.duration))"
            : track.displayArtist
    }

    private var isCurrent: Bool { model.player.track?.id == track.id }
}
