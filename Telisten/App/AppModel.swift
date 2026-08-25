import Foundation
import Observation

enum SidebarSelection: Hashable {
    case globalSearch
    case favorites
    case downloads
    case chat(String)
}

private struct MusicChatIndexEntry: Codable {
    var hasMusic: Bool
    var checkedAt: Date
    var musicCount: Int? = nil
}

@MainActor
@Observable
final class AppModel {
    private static let chatMusicPageSize: Int32 = 30
    private static let cacheLimitDefaultsKey = "offlineCache.limitBytes"

    var phase: ConnectionPhase = .signedOut
    var hasCredentials = false
    var accounts: [TelegramAccount] = []
    var activeAccountID: String?
    var isAddingAccount = false
    var chats: [MusicChat] = []
    var selected: SidebarSelection?
    var selectedChat: MusicChat?
    var tracks: [Track] = []
    var searchText = ""
    var isGlobalSearch = false
    var isLoading = false
    var isLoadingMore = false
    var hasMoreTracks = false
    var errorMessage: String?
    var playlists: [MusicChat] = []
    var playlistTrack: Track?
    var showPlaylistSheet = false
    var isSavingToPlaylist = false
    var lyricsState: LyricsLoadState = .idle
    var lyricsCandidates: [TrackLyrics] = []
    var commentsState: CommentsLoadState = .idle
    var isSendingComment = false
    var isIndexingChats = false
    var voteStates: [String: VoteState] = [:]
    private(set) var isDemo = false
    var downloads: [String: DownloadStatus] = [:]
    var cachedIDs: Set<String> = []
    var favorites: Set<String> = []
    var knownTracks: [String: Track] = [:]
    var artworkData: [String: Data] = [:]
    var chatAvatarData: [String: Data] = [:]
    var accountAvatarData: [String: Data] = [:]
    var chatMusicCounts: [String: Int] = [:]
    var queue: [Track] = []
    var currentQueueIndex: Int?
    var playbackMode: PlaybackMode = .order
    var showNowPlaying = false
    var cacheBytes: Int64 = 0
    var cacheLimitBytes: Int64
    var isDeletingPlaylist = false
    var deletingPlaylistTrackIDs: Set<String> = []
    var renamingPlaylistIDs: Set<String> = []
    var showChats = false {
        didSet { UserDefaults.standard.set(showChats, forKey: "library.showChats") }
    }

    var canOpenLibrary: Bool {
        guard !isAddingAccount else { return false }
        return !accounts.isEmpty || !cachedIDs.isEmpty || !playlists.isEmpty
    }

    let player = AudioPlayer()

    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let cache: CacheStore
    @ObservationIgnored private let localLibrary: LocalLibraryStore
    @ObservationIgnored private let artworkStore: ArtworkStore
    @ObservationIgnored private let chatAvatarStore: ChatAvatarStore
    @ObservationIgnored private let telegram: TelegramService
    @ObservationIgnored private let lyrics: LyricsService
    @ObservationIgnored private var downloadTasks: [String: Task<URL, Error>] = [:]
    @ObservationIgnored private var activeTransfers: [String: ProgressiveAudioTransfer] = [:]
    @ObservationIgnored private var artworkLoading: Set<String> = []
    @ObservationIgnored private var artworkResolved: Set<String> = []
    @ObservationIgnored private var avatarLoading: Set<String> = []
    @ObservationIgnored private var avatarResolved: Set<String> = []
    @ObservationIgnored private var accountAvatarLoading: Set<String> = []
    @ObservationIgnored private var accountAvatarResolved: Set<String> = []
    @ObservationIgnored private var allChats: [MusicChat] = []
    @ObservationIgnored private var musicChatIndex: [String: MusicChatIndexEntry] = [:]
    @ObservationIgnored private var playlistOrders: [String: [String]] = [:]
    @ObservationIgnored private var playlistTrackMirrors: [String: [Track]] = [:]
    @ObservationIgnored private var sharedDownloadedTracks: [String: Track] = [:]
    @ObservationIgnored private var trackSearchOffsetID: Int32 = 0
    @ObservationIgnored private var remoteHasMoreTracks = false
    @ObservationIgnored private var visibleTrackLimit = 30
    @ObservationIgnored private var musicChatIndexTask: Task<Void, Never>?
    @ObservationIgnored private var commentsTrackID: String?
    @ObservationIgnored private var loginPhone = ""
    @ObservationIgnored private var previousAccountID: String?

    init() {
        let defaults = UserDefaults.standard
        let storedCacheLimit = defaults.object(forKey: Self.cacheLimitDefaultsKey) == nil
            ? CacheLimits.defaultValue
            : Int64(defaults.integer(forKey: Self.cacheLimitDefaultsKey))
        let cacheLimit = min(max(storedCacheLimit, CacheLimits.minimum), CacheLimits.maximum)
        let keychain = KeychainStore()
        let cache = CacheStore(limit: cacheLimit)
        let localLibrary = LocalLibraryStore()
        cacheLimitBytes = cacheLimit
        self.keychain = keychain
        self.cache = cache
        self.localLibrary = localLibrary
        artworkStore = ArtworkStore()
        chatAvatarStore = ChatAvatarStore()
        telegram = TelegramService(keychain: keychain)
        lyrics = LyricsService()
        hasCredentials = (try? TelegramCredentials.appCredentials()) != nil
        cachedIDs = cache.initialCachedTrackIDs
        cacheBytes = cache.initialByteCount
        sharedDownloadedTracks = localLibrary.downloadedTracks
        restoreAccounts()
        restoreLibrary()
        player.onFinished = { [weak self] in self?.trackFinished() }
        player.onNext = { [weak self] in self?.next() }
        player.onPrevious = { [weak self] in self?.previous() }
        player.onError = { [weak self] message in self?.errorMessage = message }
    }

    func start() async {
        await refreshCacheUsage()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--offline") {
            phase = canOpenLibrary ? .ready : .signedOut
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            await loadDemo()
            return
        }
        #endif
        do {
            let credentials = try TelegramCredentials.appCredentials()
            try await telegram.configure(credentials)
            hasCredentials = true
        } catch {
            hasCredentials = false
            phase = canOpenLibrary ? .ready : .signedOut
            if !canOpenLibrary {
                errorMessage = UserFacingError.message(for: error)
            }
            return
        }
        if let activeAccountID {
            await telegram.useAccount(activeAccountID)
        }
        guard await telegram.hasAuthorizedSession() else {
            phase = .signedOut
            return
        }
        do {
            phase = .connecting
            allChats = mergedChats(try await telegram.restoreSession(), with: playlists)
            await refreshActiveAccountProfile()
            applyMusicChatIndex()
            await refreshPlaylists()
            phase = .ready
            beginMusicChatIndexing()
        } catch {
            phase = canOpenLibrary ? .ready : .signedOut
            if UserFacingError.isExpiredTelegramSession(error) {
                await telegram.discardSession()
            }
            if !canOpenLibrary {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    func requestCode(phone: String) async {
        loginPhone = phone
        await performLoginWork {
            let result = try await telegram.sendCode(to: phone)
            try await apply(result)
        }
    }

    func submitLoginEmail(_ email: String) async {
        await performLoginWork {
            let hint = try await telegram.sendLoginEmailCode(to: email)
            phase = .emailVerification(email: email, hint: "Verification code sent to \(hint)")
        }
    }

    func submitEmailVerification(_ code: String) async {
        await performLoginWork {
            let result = try await telegram.verifyLoginEmail(code: code)
            try await apply(result)
        }
    }

    func submitCode(_ code: String) async {
        await performLoginWork {
            switch try await telegram.signIn(code: code) {
            case .ready:
                try await finishLogin()
            case let .password(hint):
                phase = .password(hint: hint)
            }
        }
    }

    func submitPassword(_ password: String) async {
        await performLoginWork {
            try await telegram.checkPassword(password)
            try await finishLogin()
        }
    }

    func restartLogin() {
        phase = .signedOut
        errorMessage = nil
    }

    var activeAccount: TelegramAccount? {
        guard let activeAccountID else { return nil }
        return accounts.first { $0.id == activeAccountID }
    }

    func addAccount() async {
        guard !isAddingAccount else { return }
        persistLibrary()
        previousAccountID = activeAccountID
        isAddingAccount = true
        activeAccountID = "account-\(UUID().uuidString.lowercased())"
        resetForAccountTransition()
        restoreLibrary()
        if let activeAccountID {
            await telegram.useAccount(activeAccountID, clearExisting: true)
        }
        phase = .signedOut
    }

    func cancelAddingAccount() async {
        guard isAddingAccount else { return }
        await telegram.discardSession()
        isAddingAccount = false
        activeAccountID = previousAccountID
        previousAccountID = nil
        if let activeAccountID {
            await activateAccount(activeAccountID)
        } else {
            resetForAccountTransition()
            phase = .signedOut
        }
    }

    func switchAccount(to account: TelegramAccount) async {
        guard account.id != activeAccountID, !isAddingAccount else { return }
        persistLibrary()
        activeAccountID = account.id
        persistAccounts()
        await activateAccount(account.id)
    }

    func logOut() async {
        musicChatIndexTask?.cancel()
        let removedAccountID = activeAccountID
        persistLibrary()
        await telegram.logOut()
        if let removedAccountID {
            accounts.removeAll { $0.id == removedAccountID }
        }
        isAddingAccount = false
        previousAccountID = nil
        if let next = accounts.first {
            activeAccountID = next.id
            persistAccounts()
            await activateAccount(next.id)
        } else {
            activeAccountID = "legacy"
            persistAccounts()
            await telegram.useAccount("legacy", clearExisting: true)
            resetForAccountTransition()
            restoreLibrary()
            phase = .signedOut
        }
    }

    func select(_ selection: SidebarSelection?) async {
        selected = selection
        searchText = ""
        hasMoreTracks = false
        switch selection {
        case .globalSearch:
            isGlobalSearch = true
            selectedChat = nil
            tracks = []
        case let .chat(id):
            isGlobalSearch = false
            selectedChat = allChats.first(where: { $0.id == id })
            await loadTracks()
        case .favorites:
            isGlobalSearch = false
            selectedChat = nil
            tracks = favorites.compactMap { knownTracks[$0] }.sorted { $0.date > $1.date }
        case .downloads:
            isGlobalSearch = false
            selectedChat = nil
            tracks = cachedIDs.compactMap { knownTracks[$0] }.sorted { $0.date > $1.date }
        case nil:
            isGlobalSearch = false
            selectedChat = nil
            tracks = []
        }
    }

    func loadTracks() async {
        guard let chat = selectedChat else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        trackSearchOffsetID = 0
        remoteHasMoreTracks = true
        visibleTrackLimit = Int(Self.chatMusicPageSize)

        if query.isEmpty {
            tracks = Array(cachedTracks(in: chat).prefix(visibleTrackLimit))
        } else {
            tracks = []
        }

        isLoading = tracks.isEmpty
        defer { isLoading = false }
        do {
            let rawValues = try await telegram.searchMusic(
                in: chat,
                query: query,
                limit: Self.chatMusicPageSize
            )
            let values = deduplicated(rawValues)
            install(values)
            if query.isEmpty { mergePlaylistTracks(values, in: chat, appending: false) }
            trackSearchOffsetID = rawValues.last?.messageID ?? 0
            remoteHasMoreTracks = rawValues.count == Int(Self.chatMusicPageSize)
            if query.isEmpty {
                let cached = cachedTracks(in: chat)
                tracks = Array(cached.prefix(visibleTrackLimit))
                hasMoreTracks = cached.count > tracks.count || remoteHasMoreTracks
            } else {
                tracks = arranged(values, in: chat)
                hasMoreTracks = remoteHasMoreTracks
            }
            if !values.isEmpty { rememberMusic(in: chat) }
            errorMessage = nil
        } catch {
            if query.isEmpty {
                let cached = cachedTracks(in: chat)
                hasMoreTracks = cached.count > tracks.count
            }
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func search() async {
        if isGlobalSearch {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                tracks = []
                return
            }
            #if DEBUG
            if isDemo {
                tracks = knownTracks.values
                    .filter {
                        $0.title.localizedCaseInsensitiveContains(query)
                            || $0.artist.localizedCaseInsensitiveContains(query)
                            || $0.fileName.localizedCaseInsensitiveContains(query)
                    }
                    .sorted { $0.date > $1.date }
                hasMoreTracks = false
                errorMessage = nil
                return
            }
            #endif
            isLoading = true
            defer { isLoading = false }
            do {
                let values = deduplicated(try await telegram.searchAllMusic(query: query))
                install(values)
                tracks = values
                hasMoreTracks = false
                errorMessage = nil
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        } else {
            await loadTracks()
        }
    }

    func loadMoreTracks() async {
        guard !isGlobalSearch,
              hasMoreTracks,
              !isLoading,
              !isLoadingMore,
              let chat = selectedChat else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoadingMore = true
        defer { isLoadingMore = false }
        var revealedCachedPage = false

        if query.isEmpty {
            let cached = cachedTracks(in: chat)
            if cached.count > tracks.count {
                visibleTrackLimit = min(
                    cached.count,
                    max(visibleTrackLimit, tracks.count) + Int(Self.chatMusicPageSize)
                )
                tracks = Array(cached.prefix(visibleTrackLimit))
                revealedCachedPage = true
            }
        }

        do {
            if remoteHasMoreTracks {
                let previousOffset = trackSearchOffsetID
                let values = try await telegram.searchMusic(
                    in: chat,
                    query: query,
                    offsetID: previousOffset,
                    limit: Self.chatMusicPageSize
                )
                let deduplicatedValues = deduplicated(values)
                install(deduplicatedValues)
                if query.isEmpty { mergePlaylistTracks(deduplicatedValues, in: chat, appending: true) }
                let nextOffset = values.last?.messageID ?? previousOffset
                trackSearchOffsetID = nextOffset
                remoteHasMoreTracks = values.count == Int(Self.chatMusicPageSize)
                    && nextOffset != previousOffset

                if query.isEmpty {
                    let cached = cachedTracks(in: chat)
                    if !revealedCachedPage {
                        visibleTrackLimit = min(
                            cached.count,
                            visibleTrackLimit + Int(Self.chatMusicPageSize)
                        )
                    }
                    tracks = Array(cached.prefix(visibleTrackLimit))
                    hasMoreTracks = cached.count > tracks.count || remoteHasMoreTracks
                } else {
                    let existing = Set(tracks.map(\.id))
                    let additions = deduplicated(values).filter { !existing.contains($0.id) }
                    tracks = arranged(tracks + additions, in: chat)
                    hasMoreTracks = remoteHasMoreTracks
                }
            } else if query.isEmpty {
                let cached = cachedTracks(in: chat)
                hasMoreTracks = cached.count > tracks.count
            } else {
                hasMoreTracks = false
            }
            errorMessage = nil
        } catch {
            if query.isEmpty {
                let cached = cachedTracks(in: chat)
                hasMoreTracks = cached.count > tracks.count || remoteHasMoreTracks
            }
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func play(_ track: Track, from list: [Track]? = nil) {
        let source = list ?? tracks
        queue = source
        currentQueueIndex = source.firstIndex(of: track)
        persistLibrary()
        resetTrackDetails(ifChangingTo: track)
        player.beginLoading(track)
        Task { await prepareAndPlay(track) }
    }

    func voteState(for track: Track) -> VoteState {
        voteStates[track.id] ?? VoteState(count: track.upvoteCount ?? 0, chosen: track.didUpvote ?? false)
    }

    func isPlaylistTrack(_ track: Track) -> Bool {
        playlists.contains { $0.id == track.chatID }
    }

    func isPlaylist(_ chat: MusicChat) -> Bool {
        playlists.contains { $0.id == chat.id }
    }

    func moveTracks(from source: IndexSet, to destination: Int) {
        guard let chat = selectedChat, isPlaylist(chat), !source.isEmpty else { return }
        let sourceIndices = source.sorted()
        let moving = sourceIndices.map { tracks[$0] }
        var remaining = tracks
        for index in sourceIndices.reversed() {
            remaining.remove(at: index)
        }
        let removedBeforeDestination = sourceIndices.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertionIndex)
        tracks = remaining
        let visibleIDs = Set(remaining.map(\.id))
        let hiddenTracks = (playlistTrackMirrors[chat.id] ?? []).filter {
            !visibleIDs.contains($0.id)
        }
        let completeMirror = remaining + hiddenTracks
        playlistTrackMirrors[chat.id] = completeMirror
        playlistOrders[chat.id] = completeMirror.map(\.id)
        persistLibrary()
    }

    func upvote(_ track: Track) {
        var current = voteState(for: track)
        guard !current.chosen, !current.isSending else { return }
        let previous = current
        current.count += 1
        current.chosen = true
        current.isSending = true
        voteStates[track.id] = current

        Task {
            #if DEBUG
            if isDemo {
                voteStates[track.id]?.isSending = false
                return
            }
            #endif
            guard let chat = allChats.first(where: { $0.id == track.chatID }) else {
                voteStates[track.id] = previous
                errorMessage = "The music source is no longer available."
                return
            }
            do {
                try await telegram.upvote(track, in: chat)
                voteStates[track.id]?.isSending = false
            } catch {
                voteStates[track.id] = previous
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    func openPlaylistPicker(for track: Track) {
        playlistTrack = track
        showPlaylistSheet = true
    }

    func save(_ track: Track, to playlist: MusicChat) async -> Bool {
        isSavingToPlaylist = true
        defer { isSavingToPlaylist = false }
        #if DEBUG
        if isDemo { return true }
        #endif
        guard let source = allChats.first(where: { $0.id == track.chatID }) else {
            errorMessage = "The music source is no longer available."
            return false
        }
        do {
            try await telegram.save(track, from: source, to: playlist)
            mirrorSavedTrack(track, in: playlist)
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }

    func createPlaylist(named name: String, saving track: Track) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isSavingToPlaylist = true
        defer { isSavingToPlaylist = false }
        #if DEBUG
        if isDemo {
            let playlist = MusicChat(
                id: "c:\(3_000 + playlists.count)",
                peerID: Int64(3_000 + playlists.count),
                accessHash: 1,
                kind: .channel,
                title: trimmed,
                username: nil
            )
            playlists.append(playlist)
            allChats.append(playlist)
            chats.append(playlist)
            mirrorSavedTrack(track, in: playlist)
            return true
        }
        #endif
        guard let source = allChats.first(where: { $0.id == track.chatID }) else {
            errorMessage = "The music source is no longer available."
            return false
        }
        do {
            let playlist = try await telegram.createPlaylist(named: trimmed)
            playlists.append(playlist)
            allChats.append(playlist)
            try await telegram.save(track, from: source, to: playlist)
            mirrorSavedTrack(track, in: playlist)
            rememberMusic(in: playlist)
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }

    func deletePlaylist(_ playlist: MusicChat) async -> Bool {
        guard isPlaylist(playlist) else { return false }
        isDeletingPlaylist = true
        defer { isDeletingPlaylist = false }
        #if DEBUG
        if !isDemo {
            do {
                try await telegram.deletePlaylist(playlist)
            } catch {
                errorMessage = UserFacingError.message(for: error)
                return false
            }
        }
        #else
        do {
            try await telegram.deletePlaylist(playlist)
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
        #endif

        playlists.removeAll { $0.id == playlist.id }
        allChats.removeAll { $0.id == playlist.id }
        chats.removeAll { $0.id == playlist.id }
        musicChatIndex.removeValue(forKey: playlist.id)
        chatMusicCounts.removeValue(forKey: playlist.id)
        chatAvatarData.removeValue(forKey: playlist.id)
        playlistOrders.removeValue(forKey: playlist.id)
        playlistTrackMirrors.removeValue(forKey: playlist.id)
        if selectedChat?.id == playlist.id {
            selected = nil
            selectedChat = nil
            tracks = []
        }
        persistMusicChatIndex()
        persistLibrary()
        errorMessage = nil
        return true
    }

    func delete(_ track: Track, from playlist: MusicChat) async {
        guard isPlaylist(playlist), !deletingPlaylistTrackIDs.contains(track.id) else { return }
        deletingPlaylistTrackIDs.insert(track.id)
        defer { deletingPlaylistTrackIDs.remove(track.id) }

        #if DEBUG
        if !isDemo {
            do {
                try await telegram.delete(track, from: playlist)
            } catch {
                errorMessage = UserFacingError.message(for: error)
                return
            }
        }
        #else
        do {
            try await telegram.delete(track, from: playlist)
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return
        }
        #endif

        tracks.removeAll { $0.id == track.id }
        if var mirroredTracks = playlistTrackMirrors[playlist.id] {
            mirroredTracks.removeAll { $0.id == track.id }
            playlistTrackMirrors[playlist.id] = mirroredTracks
        } else {
            playlistTrackMirrors[playlist.id] = tracks
        }
        if var order = playlistOrders[playlist.id] {
            order.removeAll { $0 == track.id }
            playlistOrders[playlist.id] = order
        } else {
            playlistOrders[playlist.id] = playlistTrackMirrors[playlist.id]?.map(\.id) ?? []
        }
        persistLibrary()
        errorMessage = nil
    }

    func renamePlaylist(_ playlist: MusicChat, to rawTitle: String) async -> Bool {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlaylist(playlist),
              !title.isEmpty,
              title != playlist.title,
              !renamingPlaylistIDs.contains(playlist.id) else { return false }
        renamingPlaylistIDs.insert(playlist.id)
        defer { renamingPlaylistIDs.remove(playlist.id) }

        #if DEBUG
        if !isDemo {
            do {
                try await telegram.rename(playlist, to: title)
            } catch {
                errorMessage = UserFacingError.message(for: error)
                return false
            }
        }
        #else
        do {
            try await telegram.rename(playlist, to: title)
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
        #endif

        func updateTitle(in values: inout [MusicChat]) {
            guard let index = values.firstIndex(where: { $0.id == playlist.id }) else { return }
            values[index].title = title
        }
        updateTitle(in: &playlists)
        updateTitle(in: &allChats)
        updateTitle(in: &chats)
        if selectedChat?.id == playlist.id {
            selectedChat?.title = title
        }
        playlists.sort {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        persistLibrary()
        errorMessage = nil
        return true
    }

    func loadLyrics(for track: Track) async {
        if case let .loaded(value) = lyricsState, value.trackID == track.id { return }
        lyricsState = .loading
        do {
            let result = try await lyrics.lyrics(for: track)
            guard player.track?.id == track.id else { return }
            lyricsCandidates = result?.matches ?? []
            lyricsState = result.map { .loaded($0.selected) } ?? .unavailable
        } catch {
            guard player.track?.id == track.id else { return }
            lyricsCandidates = []
            lyricsState = .failed(UserFacingError.message(for: error))
        }
    }

    func selectLyrics(_ value: TrackLyrics) {
        guard player.track?.id == value.trackID,
              lyricsCandidates.contains(where: { $0.matchKey == value.matchKey }) else { return }
        lyricsState = .loaded(value)
        Task { await lyrics.select(value) }
    }

    func loadComments(for track: Track) async {
        if commentsTrackID == track.id, case .loaded = commentsState { return }
        commentsTrackID = track.id
        commentsState = .loading
        #if DEBUG
        if isDemo {
            commentsState = .loaded([])
            return
        }
        #endif
        guard let chat = allChats.first(where: { $0.id == track.chatID }) else {
            commentsState = .failed("The music source is no longer available.")
            return
        }
        do {
            let comments = try await telegram.comments(for: track, in: chat)
            guard player.track?.id == track.id else { return }
            commentsState = .loaded(comments)
        } catch {
            guard player.track?.id == track.id else { return }
            commentsState = .failed(UserFacingError.message(for: error))
        }
    }

    func addComment(_ rawText: String, to track: Track) async -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingComment else { return false }
        isSendingComment = true
        defer { isSendingComment = false }

        #if DEBUG
        if isDemo {
            let author = accounts.first(where: { $0.id == activeAccountID })?.displayName ?? "You"
            let comment = TrackComment(
                id: "demo:\(UUID().uuidString)",
                author: author,
                text: text,
                date: .now
            )
            if case let .loaded(values) = commentsState {
                commentsState = .loaded(values + [comment])
            } else {
                commentsState = .loaded([comment])
            }
            return true
        }
        #endif

        guard let chat = allChats.first(where: { $0.id == track.chatID }) else {
            errorMessage = "The music source is no longer available."
            return false
        }
        do {
            try await telegram.addComment(text, to: track, in: chat)
            commentsTrackID = nil
            await loadComments(for: track)
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }

    func loadArtwork(for track: Track) async {
        guard track.artworkThumbSize != nil || track.artworkPreview != nil,
              !artworkResolved.contains(track.id),
              artworkLoading.insert(track.id).inserted else { return }
        defer {
            artworkLoading.remove(track.id)
            artworkResolved.insert(track.id)
        }

        if let cached = await artworkStore.data(for: track) {
            artworkData[track.id] = cached
            return
        }
        if let preview = track.artworkPreview, !preview.isEmpty {
            artworkData[track.id] = preview
        }
        guard track.artworkThumbSize != nil else { return }

        #if DEBUG
        if isDemo { return }
        #endif
        if let data = try? await telegram.artwork(for: track), !data.isEmpty {
            artworkData[track.id] = data
            await artworkStore.save(data, for: track)
        }
    }

    func loadAvatar(for chat: MusicChat) async {
        guard chat.avatarPhotoID != nil,
              chat.avatarDCID != nil,
              !avatarResolved.contains(chat.id),
              avatarLoading.insert(chat.id).inserted else { return }
        defer {
            avatarLoading.remove(chat.id)
            avatarResolved.insert(chat.id)
        }

        if let cached = await chatAvatarStore.data(for: chat) {
            chatAvatarData[chat.id] = cached
            return
        }
        #if DEBUG
        if isDemo { return }
        #endif
        if let data = try? await telegram.avatar(for: chat), !data.isEmpty {
            chatAvatarData[chat.id] = data
            await chatAvatarStore.save(data, for: chat)
        }
    }

    func loadAvatar(for account: TelegramAccount) async {
        guard account.avatarPhotoID != nil, account.avatarDCID != nil else { return }
        let cacheKey = "\(account.id):\(account.avatarPhotoID ?? 0)"
        guard !accountAvatarResolved.contains(cacheKey),
              accountAvatarLoading.insert(cacheKey).inserted else { return }
        defer {
            accountAvatarLoading.remove(cacheKey)
            accountAvatarResolved.insert(cacheKey)
        }

        let peer = accountAvatarPeer(for: account)
        if let cached = await chatAvatarStore.data(for: peer) {
            accountAvatarData[account.id] = cached
            return
        }
        #if DEBUG
        if isDemo { return }
        #endif
        if let data = try? await telegram.avatar(for: account), !data.isEmpty {
            accountAvatarData[account.id] = data
            await chatAvatarStore.save(data, for: peer)
        }
    }

    func toggleFavorite(_ track: Track) {
        knownTracks[track.id] = track
        if favorites.contains(track.id) {
            favorites.remove(track.id)
        } else {
            favorites.insert(track.id)
        }
        persistLibrary()
        if selected == .favorites { tracks = favorites.compactMap { knownTracks[$0] } }
    }

    func cacheTrack(_ track: Track) {
        Task {
            do { _ = try await cachedFile(for: track) }
            catch { errorMessage = UserFacingError.message(for: error) }
        }
    }

    func refreshCacheUsage() async {
        let actualCachedIDs = await cache.cachedTrackIDs()
        cachedIDs = actualCachedIDs
        cacheBytes = await cache.totalBytes()
        reconcileSharedDownloads(with: actualCachedIDs)
        if selected == .downloads {
            tracks = actualCachedIDs.compactMap { knownTracks[$0] }.sorted { $0.date > $1.date }
        }
    }

    func setCacheLimit(_ bytes: Int64) {
        let value = min(max(bytes, CacheLimits.minimum), CacheLimits.maximum)
        guard cacheLimitBytes != value else { return }
        cacheLimitBytes = value
        UserDefaults.standard.set(value, forKey: Self.cacheLimitDefaultsKey)
        let activeTrackIDs = Set(activeTransfers.keys)
        Task {
            await cache.setLimit(value, preserving: activeTrackIDs)
            await refreshCacheUsage()
        }
    }

    func removeDownload(_ track: Track) {
        Task {
            do {
                try await cache.remove(track)
                cachedIDs.remove(track.id)
                downloads[track.id] = DownloadStatus.none
                cacheBytes = await cache.totalBytes()
                reconcileSharedDownloads(with: cachedIDs)
                if selected == .downloads { tracks.removeAll { $0.id == track.id } }
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        if playbackMode == .repeatOne, let track = player.track {
            player.seek(to: 0)
            player.play()
            if player.track?.id != track.id { play(track, from: queue) }
            return
        }
        let index: Int
        switch playbackMode {
        case .shuffle:
            let candidates = queue.indices.filter { $0 != currentQueueIndex }
            index = candidates.randomElement() ?? 0
        case .order:
            guard let currentQueueIndex, currentQueueIndex + 1 < queue.count else { return }
            index = currentQueueIndex + 1
        case .reverseOrder:
            guard let currentQueueIndex, currentQueueIndex > 0 else { return }
            index = currentQueueIndex - 1
        case .repeatOne:
            return
        }
        playQueueTrack(at: index)
    }

    func previous() {
        if player.currentTime > 5 {
            player.seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        let current = currentQueueIndex ?? 0
        let index: Int
        switch playbackMode {
        case .shuffle:
            let candidates = queue.indices.filter { $0 != currentQueueIndex }
            index = candidates.randomElement() ?? current
        case .order:
            index = max(current - 1, 0)
        case .reverseOrder:
            index = min(current + 1, queue.count - 1)
        case .repeatOne:
            index = current
        }
        playQueueTrack(at: index)
    }

    func cyclePlaybackMode() {
        playbackMode = playbackMode.next
        persistLibrary()
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        persistLibrary()
    }

    private func playQueueTrack(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentQueueIndex = index
        resetTrackDetails(ifChangingTo: queue[index])
        player.beginLoading(queue[index])
        Task { await prepareAndPlay(queue[index]) }
    }

    private func prepareAndPlay(_ track: Track) async {
        if let url = await cache.localURL(for: track) {
            guard player.track?.id == track.id else { return }
            cachedIDs.insert(track.id)
            downloads[track.id] = DownloadStatus(progress: 1, isCached: true)
            knownTracks[track.id] = track
            persistLibrary()
            player.load(track, from: url)
        } else {
            guard player.track?.id == track.id else { return }
            let transfer = await progressiveTransfer(for: track)
            player.loadStreaming(track) { offset, length in
                try await transfer.bytes(at: offset, length: length)
            }
            cacheDuringPlayback(track)
        }
        await loadLyrics(for: track)
    }

    private func cacheDuringPlayback(_ track: Track) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.cachedFile(for: track)
                await self.prefetchNextPlaylistTrack(after: track)
            } catch is CancellationError {
                return
            } catch {
                guard self.player.track?.id == track.id else { return }
                self.errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    private func prefetchNextPlaylistTrack(after track: Track) async {
        guard isPlaylistTrack(track),
              let index = currentQueueIndex,
              queue.indices.contains(index),
              queue[index].id == track.id else { return }

        let nextIndex: Int?
        switch playbackMode {
        case .order:
            nextIndex = queue.indices.contains(index + 1) ? index + 1 : nil
        case .reverseOrder:
            nextIndex = queue.indices.contains(index - 1) ? index - 1 : nil
        case .repeatOne, .shuffle:
            nextIndex = nil
        }
        guard let nextIndex else { return }

        let nextTrack = queue[nextIndex]
        do {
            _ = try await cachedFile(for: nextTrack)
        } catch {
            // Prefetch is opportunistic. Normal playback will retry if it is still needed.
        }
    }

    private func cachedFile(for track: Track) async throws -> URL {
        if let url = await cache.localURL(for: track) {
            cachedIDs.insert(track.id)
            downloads[track.id] = DownloadStatus(progress: 1, isCached: true)
            knownTracks[track.id] = track
            persistLibrary()
            return url
        }
        if let existing = downloadTasks[track.id] { return try await existing.value }
        knownTracks[track.id] = track
        persistLibrary()
        let cache = cache
        let transfer = await progressiveTransfer(for: track)
        let task = Task<URL, Error> {
            let temporary = await cache.partialLocation(for: track).dataURL
            try await transfer.downloadAll { [weak self] value in
                let bytes = await cache.totalBytes()
                await MainActor.run {
                    self?.downloads[track.id] = DownloadStatus(progress: value, isCached: false)
                    self?.cacheBytes = bytes
                }
            }
            let destination = try await cache.commit(temporary, track: track)
            await transfer.didCommit(to: destination)
            return destination
        }
        downloadTasks[track.id] = task
        defer {
            downloadTasks.removeValue(forKey: track.id)
            activeTransfers.removeValue(forKey: track.id)
        }
        do {
            let url = try await task.value
            cachedIDs.insert(track.id)
            downloads[track.id] = DownloadStatus(progress: 1, isCached: true)
            knownTracks[track.id] = track
            await refreshCacheUsage()
            persistLibrary()
            return url
        } catch {
            cacheBytes = await cache.totalBytes()
            throw error
        }
    }

    private func progressiveTransfer(for track: Track) async -> ProgressiveAudioTransfer {
        if let transfer = activeTransfers[track.id] { return transfer }
        let location = await cache.partialLocation(for: track)
        let telegram = telegram
        let sourceChat = allChats.first(where: { $0.id == track.chatID })
        let transfer = ProgressiveAudioTransfer(
            trackID: track.id,
            fileSize: track.size,
            location: location
        ) { offset, length in
            try await telegram.stream(
                track,
                sourceChat: sourceChat,
                offset: offset,
                length: length
            )
        }
        activeTransfers[track.id] = transfer
        return transfer
    }

    private func finishLogin() async throws {
        phase = .connecting
        if activeAccountID == nil {
            activeAccountID = "legacy"
        }
        allChats = mergedChats(try await telegram.loadChats(), with: playlists)
        await refreshActiveAccountProfile()
        applyMusicChatIndex()
        await refreshPlaylists()
        isAddingAccount = false
        previousAccountID = nil
        persistAccounts()
        phase = .ready
        beginMusicChatIndexing()
    }

    private func activateAccount(_ id: String) async {
        resetForAccountTransition()
        activeAccountID = id
        restoreLibrary()
        phase = .connecting
        await telegram.useAccount(id)
        guard await telegram.hasAuthorizedSession() else {
            phase = .signedOut
            return
        }
        do {
            allChats = mergedChats(try await telegram.restoreSession(), with: playlists)
            await refreshActiveAccountProfile()
            applyMusicChatIndex()
            await refreshPlaylists()
            phase = .ready
            beginMusicChatIndexing()
            errorMessage = nil
        } catch {
            phase = .signedOut
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func resetForAccountTransition() {
        musicChatIndexTask?.cancel()
        player.reset()
        allChats = []
        chats = []
        tracks = []
        selected = nil
        selectedChat = nil
        playlists = []
        playlistTrack = nil
        playlistTrackMirrors = [:]
        showPlaylistSheet = false
        showNowPlaying = false
        lyricsState = .idle
        lyricsCandidates = []
        commentsState = .idle
        commentsTrackID = nil
        voteStates = [:]
        artworkData = [:]
        artworkLoading = []
        artworkResolved = []
        chatAvatarData = [:]
        avatarLoading = []
        avatarResolved = []
        accountAvatarData = [:]
        accountAvatarLoading = []
        accountAvatarResolved = []
        chatMusicCounts = [:]
        currentQueueIndex = nil
    }

    private func refreshActiveAccountProfile() async {
        guard let profile = try? await telegram.currentAccount() else { return }
        let previousID = activeAccountID
        activeAccountID = profile.id
        if let index = accounts.firstIndex(where: { $0.id == profile.id }) {
            accounts[index] = profile
        } else {
            accounts.append(profile)
        }
        persistAccounts()
        if previousID != profile.id { persistLibrary() }
        await loadAvatar(for: profile)
    }

    private func apply(_ result: TelegramService.RequestCodeResult) async throws {
        switch result {
        case let .code(hint, isEmail):
            phase = .code(phone: loginPhone, hint: hint, isEmail: isEmail)
        case .emailSetup:
            phase = .emailAddress
        case let .password(hint):
            phase = .password(hint: hint)
        case .ready:
            try await finishLogin()
        }
    }

    private func performLoginWork(_ operation: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func install(_ values: [Track]) {
        for track in values {
            knownTracks[track.id] = track
            voteStates[track.id] = VoteState(
                count: track.upvoteCount ?? 0,
                chosen: track.didUpvote ?? false
            )
        }
        persistLibrary()
    }

    private func mergePlaylistTracks(_ values: [Track], in chat: MusicChat, appending: Bool) {
        guard isPlaylist(chat), !values.isEmpty else { return }
        let existing = playlistTrackMirrors[chat.id] ?? []
        let incomingIDs = Set(values.map(\.id))
        let retained = existing.filter { !incomingIDs.contains($0.id) }
        playlistTrackMirrors[chat.id] = appending ? retained + values : values + retained
        persistLibrary()
    }

    private func mirrorSavedTrack(_ track: Track, in playlist: MusicChat) {
        var mirrored = track
        mirrored.chatID = playlist.id
        mirrored.messageID = 0
        var values = playlistTrackMirrors[playlist.id] ?? []
        values.removeAll { $0.id == mirrored.id }
        values.insert(mirrored, at: 0)
        playlistTrackMirrors[playlist.id] = values
        if var order = playlistOrders[playlist.id], !order.isEmpty {
            order.removeAll { $0 == mirrored.id }
            order.insert(mirrored.id, at: 0)
            playlistOrders[playlist.id] = order
        }
        persistLibrary()
    }

    private func mergedChats(
        _ primary: [MusicChat],
        with supplemental: [MusicChat],
        replacingExisting: Bool = false
    ) -> [MusicChat] {
        var result = primary
        var indices = Dictionary(uniqueKeysWithValues: primary.enumerated().map { ($0.element.id, $0.offset) })
        for chat in supplemental {
            if let index = indices[chat.id] {
                if replacingExisting { result[index] = chat }
            } else {
                indices[chat.id] = result.count
                result.append(chat)
            }
        }
        return result
    }

    private func deduplicated(_ values: [Track]) -> [Track] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    private func cachedTracks(in chat: MusicChat) -> [Track] {
        let values: [Track]
        if isPlaylist(chat), let mirrored = playlistTrackMirrors[chat.id] {
            values = mirrored
        } else {
            values = knownTracks.values
                .filter { $0.chatID == chat.id }
                .sorted { lhs, rhs in
                    if lhs.date == rhs.date { return lhs.messageID > rhs.messageID }
                    return lhs.date > rhs.date
                }
        }
        return arranged(values, in: chat)
    }

    private func accountAvatarPeer(for account: TelegramAccount) -> MusicChat {
        MusicChat(
            id: "account:\(account.id)",
            peerID: account.userID,
            accessHash: nil,
            kind: .user,
            title: account.displayName,
            username: account.username,
            avatarPhotoID: account.avatarPhotoID,
            avatarDCID: account.avatarDCID
        )
    }

    private func arranged(_ values: [Track], in chat: MusicChat) -> [Track] {
        guard isPlaylist(chat), let order = playlistOrders[chat.id], !order.isEmpty else {
            return values
        }
        var remaining = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        var result = order.compactMap { remaining.removeValue(forKey: $0) }
        result.append(contentsOf: values.filter { remaining.removeValue(forKey: $0.id) != nil })
        return result
    }

    private func refreshPlaylists() async {
        if let values = try? await telegram.loadPlaylistChats(from: allChats) {
            playlists = values
            allChats = mergedChats(allChats, with: values, replacingExisting: true)
            persistLibrary()
        }
    }

    private func beginMusicChatIndexing() {
        musicChatIndexTask?.cancel()
        musicChatIndexTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.refreshMusicChatIndex()
        }
    }

    private func refreshMusicChatIndex() async {
        let now = Date()
        let playlistIDs = Set(playlists.map(\.id))
        let candidates = allChats.filter { chat in
            guard !playlistIDs.contains(chat.id) else { return false }
            guard let entry = musicChatIndex[chat.id] else { return true }
            guard entry.musicCount != nil else { return true }
            let maximumAge: TimeInterval = entry.hasMusic ? 7 * 24 * 60 * 60 : 24 * 60 * 60
            return now.timeIntervalSince(entry.checkedAt) >= maximumAge
        }
        guard !candidates.isEmpty else {
            isIndexingChats = false
            return
        }

        isIndexingChats = true
        defer { isIndexingChats = false }
        for chat in candidates {
            guard !Task.isCancelled else { return }
            do {
                let count = try await telegram.musicCount(in: chat)
                musicChatIndex[chat.id] = MusicChatIndexEntry(
                    hasMusic: count > 0,
                    checkedAt: .now,
                    musicCount: count
                )
                persistMusicChatIndex()
                applyMusicChatIndex()
            } catch {
                // Keep stale cache entries when a chat cannot be queried temporarily.
                if isTelegramRateLimit(error) {
                    return
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func isTelegramRateLimit(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.localizedCaseInsensitiveContains("FLOOD_WAIT")
            || message.localizedCaseInsensitiveContains("too many attempts")
            || message.localizedCaseInsensitiveContains("asked you to wait")
            || message.localizedCaseInsensitiveContains("temporarily limited")
    }

    private func rememberMusic(in chat: MusicChat) {
        let count = max(musicChatIndex[chat.id]?.musicCount ?? 0, 1)
        musicChatIndex[chat.id] = MusicChatIndexEntry(
            hasMusic: true,
            checkedAt: .now,
            musicCount: count
        )
        persistMusicChatIndex()
        applyMusicChatIndex()
    }

    private func applyMusicChatIndex() {
        let validIDs = Set(allChats.map(\.id))
        musicChatIndex = musicChatIndex.filter { validIDs.contains($0.key) }
        chats = allChats.filter { musicChatIndex[$0.id]?.hasMusic == true }
        chatMusicCounts = Dictionary(uniqueKeysWithValues: musicChatIndex.compactMap { id, entry in
            guard entry.hasMusic else { return nil }
            return (id, entry.musicCount ?? 1)
        })
    }

    private func resetTrackDetails(ifChangingTo track: Track) {
        guard player.track?.id != track.id else { return }
        lyricsState = .idle
        lyricsCandidates = []
        commentsState = .idle
        commentsTrackID = nil
    }

    #if DEBUG
    private func loadDemo() async {
        isDemo = true
        hasCredentials = true
        let demoAccount = TelegramAccount(
            id: "demo",
            userID: 1,
            displayName: "Neko",
            username: "neko"
        )
        accounts = [demoAccount]
        activeAccountID = demoAccount.id
        let source = MusicChat(
            id: "c:1001",
            peerID: 1001,
            accessHash: 1,
            kind: .channel,
            title: "Late Night Records",
            username: "latenightrecords",
            isPinned: true
        )
        let discoveries = MusicChat(
            id: "g:1002",
            peerID: 1002,
            accessHash: nil,
            kind: .group,
            title: "Music Discoveries",
            username: nil
        )
        let playlist = MusicChat(
            id: "c:2001",
            peerID: 2001,
            accessHash: 1,
            kind: .channel,
            title: "Sunday Drive",
            username: nil
        )
        chats = [source, discoveries, playlist]
        allChats = chats
        playlists = [playlist]
        chatMusicCounts = [source.id: 128, discoveries.id: 42]
        let arguments = ProcessInfo.processInfo.arguments
        let demoTrackChatID = arguments.contains("--demo-playlist") ? playlist.id : source.id
        let samples = [
            ("The Chain", "Fleetwood Mac", 271.0, 18),
            ("Midnight City", "M83", 244.0, 12),
            ("Dreams", "The Cranberries", 271.0, 9),
            ("Space Song", "Beach House", 320.0, 24),
            ("Electric Feel", "MGMT", 229.0, 7)
        ]
        let sampleTracks = samples.enumerated().map { index, item in
            Track(
                documentID: Int64(10_000 + index),
                accessHash: 1,
                fileReference: Data(),
                dcID: 2,
                messageID: Int32(500 - index),
                chatID: demoTrackChatID,
                title: item.0,
                artist: item.1,
                fileName: "\(item.0).m4a",
                mimeType: "audio/mp4",
                duration: item.2,
                size: Int64(7_000_000 + index * 800_000),
                date: .now.addingTimeInterval(TimeInterval(-index * 3_600)),
                upvoteCount: Int32(item.3),
                didUpvote: index == 3
            )
        }
        install(sampleTracks)
        queue = sampleTracks
        currentQueueIndex = 0
        player.preview(sampleTracks[0], at: 48)

        if arguments.contains("--demo-partial-cache") {
            await seedDemoPartialCache(for: sampleTracks[0])
        }
        if arguments.contains("--demo-chat") {
            selected = .chat(source.id)
            selectedChat = source
            tracks = sampleTracks
        } else if arguments.contains("--demo-playlist") {
            selected = .chat(playlist.id)
            selectedChat = playlist
            tracks = sampleTracks
        } else {
            selected = nil
            selectedChat = nil
            tracks = []
        }

        phase = .ready
        if arguments.contains("--demo-now-playing") {
            showNowPlaying = true
        }
        await loadLyrics(for: sampleTracks[0])
    }

    private func seedDemoPartialCache(for track: Track) async {
        let location = await cache.partialLocation(for: track)
        let transfer = ProgressiveAudioTransfer(
            trackID: track.id,
            fileSize: track.size,
            location: location
        ) { _, length in
            Data(repeating: 0x54, count: Int(length))
        }
        _ = try? await transfer.bytes(at: 0, length: 512 * 1_024)
        await refreshCacheUsage()
    }
    #endif

    private func trackFinished() {
        next()
    }

    private func restoreAccounts() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "telegram.accounts"),
           let values = try? JSONDecoder().decode([TelegramAccount].self, from: data) {
            accounts = values
        }
        if accounts.isEmpty,
           defaults.bool(forKey: "telegram.authorized") {
            accounts = [TelegramAccount(
                id: "legacy",
                userID: 0,
                displayName: "Telegram Account",
                username: nil
            )]
        }
        let savedID = defaults.string(forKey: "telegram.activeAccountID")
        if let savedID, accounts.contains(where: { $0.id == savedID }) {
            activeAccountID = savedID
        } else {
            activeAccountID = accounts.first?.id
        }
        persistAccounts()
    }

    private func persistAccounts() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(accounts), forKey: "telegram.accounts")
        if let activeAccountID {
            defaults.set(activeAccountID, forKey: "telegram.activeAccountID")
        } else {
            defaults.removeObject(forKey: "telegram.activeAccountID")
        }
    }

    private func accountStorageKey(_ base: String) -> String {
        guard let activeAccountID, activeAccountID != "legacy" else { return base }
        return "\(base).\(activeAccountID)"
    }

    private func restoreLibrary() {
        let defaults = UserDefaults.standard
        favorites = []
        knownTracks = [:]
        queue = []
        musicChatIndex = [:]
        playlistOrders = [:]
        playlistTrackMirrors = [:]
        playlists = []
        favorites = Set(defaults.stringArray(forKey: accountStorageKey("library.favorites")) ?? [])
        if let rawMode = defaults.string(forKey: "player.playbackMode"),
           let savedMode = PlaybackMode(rawValue: rawMode) {
            playbackMode = savedMode
        } else if defaults.bool(forKey: "player.shuffle") {
            playbackMode = .shuffle
        } else if defaults.string(forKey: "player.repeat") == "one" {
            playbackMode = .repeatOne
        } else {
            playbackMode = .order
        }
        if defaults.object(forKey: "library.showChats") != nil {
            showChats = defaults.bool(forKey: "library.showChats")
        }
        if let data = defaults.data(forKey: accountStorageKey("library.tracks")),
           let values = try? JSONDecoder().decode([Track].self, from: data) {
            knownTracks = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        }
        if let data = defaults.data(forKey: accountStorageKey("player.queue")),
           let values = try? JSONDecoder().decode([Track].self, from: data) {
            queue = values
        }
        if let data = defaults.data(forKey: accountStorageKey("music.chatIndex")),
           let values = try? JSONDecoder().decode([String: MusicChatIndexEntry].self, from: data) {
            musicChatIndex = values
        }
        if let data = defaults.data(forKey: accountStorageKey("playlist.trackOrders")),
           let values = try? JSONDecoder().decode([String: [String]].self, from: data) {
            playlistOrders = values
        }

        let mirror = localLibrary.playlistMirror(for: localMirrorAccountID)
        playlists = mirror.playlists
        playlistTrackMirrors = mirror.tracksByPlaylist
        for (playlistID, order) in mirror.trackOrders where playlistOrders[playlistID] == nil {
            playlistOrders[playlistID] = order
        }
        for track in mirror.tracksByPlaylist.values.joined() where knownTracks[track.id] == nil {
            knownTracks[track.id] = track
        }
        allChats = mergedChats(allChats, with: playlists)
        reconcileSharedDownloads(with: cachedIDs)
    }

    private func persistLibrary() {
        let defaults = UserDefaults.standard
        defaults.set(Array(favorites), forKey: accountStorageKey("library.favorites"))
        defaults.set(playbackMode.rawValue, forKey: "player.playbackMode")
        defaults.removeObject(forKey: "player.repeat")
        defaults.removeObject(forKey: "player.shuffle")
        defaults.set(try? JSONEncoder().encode(Array(knownTracks.values)), forKey: accountStorageKey("library.tracks"))
        defaults.set(try? JSONEncoder().encode(queue), forKey: accountStorageKey("player.queue"))
        defaults.set(try? JSONEncoder().encode(playlistOrders), forKey: accountStorageKey("playlist.trackOrders"))
        reconcileSharedDownloads(with: cachedIDs)
        localLibrary.savePlaylistMirror(
            LocalPlaylistMirror(
                playlists: playlists,
                tracksByPlaylist: playlistTrackMirrors,
                trackOrders: playlistOrders
            ),
            for: localMirrorAccountID
        )
    }

    private var localMirrorAccountID: String {
        activeAccountID ?? "local"
    }

    private func reconcileSharedDownloads(with actualCachedIDs: Set<String>) {
        for trackID in actualCachedIDs {
            if let track = knownTracks[trackID] {
                sharedDownloadedTracks[trackID] = track
            }
        }
        sharedDownloadedTracks = sharedDownloadedTracks.filter {
            actualCachedIDs.contains($0.key)
        }
        for (trackID, track) in sharedDownloadedTracks where knownTracks[trackID] == nil {
            knownTracks[trackID] = track
        }
        localLibrary.saveDownloadedTracks(sharedDownloadedTracks)
    }

    private func persistMusicChatIndex() {
        UserDefaults.standard.set(
            try? JSONEncoder().encode(musicChatIndex),
            forKey: accountStorageKey("music.chatIndex")
        )
    }
}
