import Foundation
import Observation

enum SidebarSelection: Hashable {
    case globalSearch
    case favorites
    case downloads
    case bot(UUID)
    case chat(String)
}

private struct MusicChatIndexEntry: Codable {
    var hasMusic: Bool
    var checkedAt: Date
}

private enum QRLoginWakeReason: Sendable {
    case update
    case expired
}

@MainActor
@Observable
final class AppModel {
    private static let chatMusicPageSize: Int32 = 30
    private static let cacheLimitDefaultsKey = "offlineCache.limitBytes"
    private static let lyricsServerDefaultsKey = "lyrics.serverURL"

    var phase: ConnectionPhase = .signedOut
    var qrCodeLoginState: QRCodeLoginState = .idle
    var hasCredentials = false
    var accounts: [TelegramAccount] = []
    var activeAccountID: String?
    var isAddingAccount = false
    var isCancellingAccount = false
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
    var queue: [Track] = []
    var currentQueueIndex: Int?
    var playbackMode: PlaybackMode = .order
    var showNowPlaying = false
    var showListenTogetherSheet = false
    var listenTogetherState: ListenTogetherState = .idle
    var cacheBytes: Int64 = 0
    var cacheLimitBytes: Int64
    var lyricsServerURL: URL
    var searchBots: [SearchBotConfig] = []
    var savedChatIDs: Set<String> = []
    var activeBotSearchConfig: SearchBotConfig?
    var botSearchMessages: [BotSearchMessage] = []
    var isBotSearching = false
    var botSearchError: String?
    var showBotSearch = false
    var isDeletingPlaylist = false
    var deletingPlaylistTrackIDs: Set<String> = []
    var renamingPlaylistIDs: Set<String> = []
    var downloadingPlaylistIDs: Set<String> = []
    var showChats = false {
        didSet { UserDefaults.standard.set(showChats, forKey: "library.showChats") }
    }

    var canOpenLibrary: Bool {
        guard !isAddingAccount else { return false }
        return !accounts.isEmpty || !cachedIDs.isEmpty || !playlists.isEmpty
    }

    private var canOpenOfflineLibrary: Bool {
        !cachedIDs.isEmpty || !sharedDownloadedTracks.isEmpty || !playlists.isEmpty
    }

    let player = AudioPlayer()

    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let cache: CacheStore
    @ObservationIgnored private let localLibrary: LocalLibraryStore
    @ObservationIgnored private let artworkStore: ArtworkStore
    @ObservationIgnored private let chatAvatarStore: ChatAvatarStore
    @ObservationIgnored private let telegram: TelegramService
    @ObservationIgnored private let lyrics: LyricsService
    @ObservationIgnored private let listenTogetherBroadcaster = ListenTogetherBroadcaster()
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
    @ObservationIgnored private var qrCodeLoginTask: Task<Void, Never>?
    @ObservationIgnored private var qrCodeLoginOperationID: UUID?
    @ObservationIgnored private var passwordRequestedByQRCode = false
    @ObservationIgnored private var postLoginRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var listenTogetherTask: Task<Void, Never>?
    @ObservationIgnored private var broadcastTrackID: String?
    @ObservationIgnored private var broadcastStartedAt: Date?
    @ObservationIgnored private var broadcastStartOffset: TimeInterval = 0
    @ObservationIgnored private var broadcastWasPlaying = false
    @ObservationIgnored private var lastCallTitleUpdate: Date?
    @ObservationIgnored private var listenerMetadataTitle: String?
    @ObservationIgnored private var listenerMetadataObservedAt: Date?
    @ObservationIgnored private var listenTogetherInviteLinks: [String: URL] = [:]
    @ObservationIgnored private var botSearchOperationID: UUID?
    @ObservationIgnored private var botSearchConversationStartID: Int32?
    @ObservationIgnored private var botSearchRefreshTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let storedCacheLimit = defaults.object(forKey: Self.cacheLimitDefaultsKey) == nil
            ? CacheLimits.defaultValue
            : Int64(defaults.integer(forKey: Self.cacheLimitDefaultsKey))
        let cacheLimit = min(max(storedCacheLimit, CacheLimits.minimum), CacheLimits.maximum)
        let lyricsServerURL = defaults.string(forKey: Self.lyricsServerDefaultsKey)
            .flatMap(LyricsServerConfiguration.normalizedURL(from:))
            ?? LyricsServerConfiguration.defaultURL
        let keychain = KeychainStore()
        let cache = CacheStore(limit: cacheLimit)
        let localLibrary = LocalLibraryStore()
        cacheLimitBytes = cacheLimit
        self.lyricsServerURL = lyricsServerURL
        self.keychain = keychain
        self.cache = cache
        self.localLibrary = localLibrary
        artworkStore = ArtworkStore()
        chatAvatarStore = ChatAvatarStore()
        telegram = TelegramService(keychain: keychain)
        lyrics = LyricsService(provider: LRCLIBProvider(serverURL: lyricsServerURL))
        hasCredentials = (try? TelegramCredentials.appCredentials()) != nil
        cachedIDs = cache.initialCachedTrackIDs
        cacheBytes = cache.initialByteCount
        sharedDownloadedTracks = localLibrary.downloadedTracks
        restoreSearchBots()
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
        let initiallySelectedAccountID = activeAccountID
        for candidateID in sessionRestoreCandidateIDs() {
            await telegram.useAccount(candidateID)
            guard await telegram.hasAuthorizedSession() else { continue }

            if activeAccountID != candidateID {
                activeAccountID = candidateID
                restoreLibrary()
            }

            do {
                phase = .connecting
                allChats = mergedChats(try await telegram.restoreSession(), with: playlists)
                await refreshActiveAccountProfile()
                applyMusicChatIndex()
                await refreshPlaylists()
                phase = .ready
                beginMusicChatIndexing()
                errorMessage = nil
                return
            } catch {
                if UserFacingError.isExpiredTelegramSession(error) {
                    // A stale registry entry must not hide another account with
                    // a valid synchronized session. Remove only the explicitly
                    // rejected session, then continue through the registry.
                    await telegram.discardSession()
                    continue
                }

                // Connectivity failures are common during launch and do not
                // invalidate this or any other stored account. Keep the chosen
                // account and its offline library available for a later retry.
                phase = canOpenLibrary ? .ready : .signedOut
                if !canOpenLibrary {
                    errorMessage = UserFacingError.message(for: error)
                }
                return
            }
        }

        // Keep login scoped to the user's preferred registry entry even though
        // TelegramService tried additional candidates while looking for a saved
        // session. This prevents a failed default-account probe from deciding
        // where the next authorization is stored.
        activeAccountID = initiallySelectedAccountID
        await telegram.useAccount(initiallySelectedAccountID ?? "legacy")
        restoreLibrary()
        phase = canOpenOfflineLibrary ? .ready : .signedOut
    }

    func requestCode(phone: String) async {
        stopQRCodeLogin()
        passwordRequestedByQRCode = false
        loginPhone = phone
        await performLoginWork {
            let result = try await telegram.sendCode(to: phone)
            try await apply(result)
        }
    }

    func startQRCodeLogin() async {
        guard qrCodeLoginState == .idle else { return }
        await prepareQRCodeLogin()
    }

    func refreshQRCodeLogin() async {
        stopQRCodeLogin()
        await telegram.restartPendingQRCodeLoginTransport()
        await prepareQRCodeLogin()
    }

    private func prepareQRCodeLogin() async {
        let operationID = UUID()
        qrCodeLoginOperationID = operationID
        qrCodeLoginState = .loading
        errorMessage = nil

        if !isAddingAccount {
            previousAccountID = activeAccountID
            isAddingAccount = true
            activeAccountID = "account-\(UUID().uuidString.lowercased())"
            resetForAccountTransition()
            restoreLibrary()
            if let activeAccountID {
                await telegram.useAccount(activeAccountID, clearExisting: true)
            }
        }

        guard qrCodeLoginOperationID == operationID, !Task.isCancelled else { return }
        phase = .signedOut
        let locallyAuthorizedIDs = Set(keychain.availableSessionAccountIDs())
        let exceptUserIDs = accounts.compactMap { account -> Int64? in
            guard locallyAuthorizedIDs.contains(account.id), account.userID > 0 else { return nil }
            return account.userID
        }
        qrCodeLoginTask = Task { [weak self] in
            await self?.runQRCodeLogin(exceptUserIDs: exceptUserIDs, operationID: operationID)
        }
    }

    func usePhoneNumberLogin() async {
        stopQRCodeLogin()
        await telegram.restartPendingQRCodeLoginTransport()
        passwordRequestedByQRCode = false
        phase = .signedOut
        errorMessage = nil
    }

    private func stopQRCodeLogin() {
        qrCodeLoginOperationID = nil
        qrCodeLoginTask?.cancel()
        qrCodeLoginTask = nil
        qrCodeLoginState = .idle
    }

    private func runQRCodeLogin(exceptUserIDs: [Int64], operationID: UUID) async {
        var currentCode: TelegramService.QRLoginCode?
        var consecutiveFailures = 0

        while !Task.isCancelled {
            do {
                let updateRevision = await telegram.currentLoginTokenUpdateRevision()
                let result = try await telegram.exportQRCodeLogin(exceptUserIDs: exceptUserIDs)
                guard !Task.isCancelled, qrCodeLoginOperationID == operationID else { return }
                consecutiveFailures = 0
                switch result {
                case let .code(code):
                    currentCode = code
                    qrCodeLoginState = .waiting(url: code.url, expiresAt: code.expiresAt)
                    let wake = await waitForQRCodeLoginWake(
                        after: updateRevision,
                        expiresAt: code.expiresAt
                    )
                    guard !Task.isCancelled, qrCodeLoginOperationID == operationID else { return }
                    if case .expired = wake {
                        // Keep the last code visible while Telegram issues its
                        // replacement. The auth key is deliberately retained: an
                        // approval can race this local refresh boundary.
                        qrCodeLoginState = .waiting(
                            url: code.url,
                            expiresAt: code.expiresAt,
                            status: "Refreshing code…"
                        )
                    } else {
                        qrCodeLoginState = .loading
                    }

                case let .password(hint):
                    passwordRequestedByQRCode = true
                    qrCodeLoginState = .idle
                    phase = .password(hint: hint)
                    qrCodeLoginTask = nil
                    qrCodeLoginOperationID = nil
                    return

                case let .ready(profile):
                    qrCodeLoginState = .idle
                    qrCodeLoginTask = nil
                    qrCodeLoginOperationID = nil
                    isLoading = true
                    do {
                        try await completeLogin(profile: profile)
                    } catch {}
                    isLoading = false
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, qrCodeLoginOperationID == operationID else { return }
                consecutiveFailures += 1
                let message = UserFacingError.message(for: error)
                if consecutiveFailures >= 4 {
                    qrCodeLoginState = .failed(message)
                    qrCodeLoginTask = nil
                    qrCodeLoginOperationID = nil
                    return
                }
                if let currentCode {
                    qrCodeLoginState = .waiting(
                        url: currentCode.url,
                        expiresAt: currentCode.expiresAt,
                        status: "Connection interrupted — retrying"
                    )
                } else {
                    qrCodeLoginState = .loading
                }
                try? await Task.sleep(for: .seconds(Double(consecutiveFailures * 2)))
            }
        }
    }

    private func waitForQRCodeLoginWake(
        after revision: UInt64,
        expiresAt: Date
    ) async -> QRLoginWakeReason {
        let telegram = telegram
        return await withTaskGroup(of: QRLoginWakeReason.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    if await telegram.currentLoginTokenUpdateRevision() != revision {
                        return .update
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(150))
                    } catch {
                        return .expired
                    }
                }
                return .expired
            }
            group.addTask {
                // Refresh just before the token boundary so the current code
                // remains on screen while the next request begins.
                let remaining = max(0.25, expiresAt.timeIntervalSinceNow - 2)
                try? await Task.sleep(for: .seconds(remaining))
                return .expired
            }
            let first = await group.next() ?? .expired
            group.cancelAll()
            return first
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
            case let .ready(profile):
                try await completeLogin(profile: profile)
            case let .password(hint):
                passwordRequestedByQRCode = false
                phase = .password(hint: hint)
            }
        }
    }

    func submitPassword(_ password: String) async {
        await performLoginWork {
            let profile = try await telegram.checkPassword(password)
            try await completeLogin(profile: profile)
            passwordRequestedByQRCode = false
        }
    }

    func restartLogin() async {
        let shouldDiscardPendingQRCodeSession = passwordRequestedByQRCode
        stopQRCodeLogin()
        passwordRequestedByQRCode = false
        if shouldDiscardPendingQRCodeSession {
            isLoading = true
            await telegram.discardPendingQRCodeLoginSession()
            isLoading = false
        }
        phase = .signedOut
        errorMessage = nil
    }

    var activeAccount: TelegramAccount? {
        guard let activeAccountID else { return nil }
        return accounts.first { $0.id == activeAccountID }
    }

    func addAccount() async {
        guard !isAddingAccount else { return }
        stopQRCodeLogin()
        await stopListenTogether(endHostedCall: true)
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
        guard isAddingAccount, !isCancellingAccount, !isLoading else { return }
        isCancellingAccount = true
        let accountToRestore = previousAccountID
        stopQRCodeLogin()
        await telegram.discardSession()
        isAddingAccount = false
        activeAccountID = accountToRestore
        previousAccountID = nil
        isCancellingAccount = false
        if let activeAccountID {
            await activateAccount(activeAccountID)
        } else {
            resetForAccountTransition()
            phase = .signedOut
        }
    }

    func switchAccount(to account: TelegramAccount) async {
        guard account.id != activeAccountID, !isAddingAccount else { return }
        stopQRCodeLogin()
        await stopListenTogether(endHostedCall: true)
        persistLibrary()
        activeAccountID = account.id
        persistAccounts()
        await activateAccount(account.id)
    }

    func logOut() async {
        stopQRCodeLogin()
        await stopListenTogether(endHostedCall: true)
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
        case let .bot(id):
            isGlobalSearch = false
            selectedChat = nil
            tracks = []
            guard let config = searchBots.first(where: { $0.id == id }) else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let bot = try await telegram.searchBotChat(config)
                guard selected == .bot(id) else { return }
                selectedChat = bot
                await loadTracks()
            } catch {
                guard selected == .bot(id) else { return }
                errorMessage = UserFacingError.message(for: error)
            }
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

    func toggleSavedChat(_ chat: MusicChat) {
        guard !playlists.contains(where: { $0.id == chat.id }) else { return }
        if savedChatIDs.contains(chat.id) {
            savedChatIDs.remove(chat.id)
        } else {
            savedChatIDs.insert(chat.id)
        }
        persistSavedChats()
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

    func beginBotSearch(using config: SearchBotConfig) async {
        guard !isBotSearching else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            botSearchError = "Enter a song, artist, or album first."
            return
        }

        activeBotSearchConfig = config
        botSearchMessages = []
        botSearchConversationStartID = nil
        botSearchError = nil
        showBotSearch = true
        let command = config.command(for: query)
        #if DEBUG
        if isDemo {
            await loadDemoBotSearch(config: config, query: query, command: command)
            return
        }
        #endif
        await performBotSearch(startingWith: command) {
            try await telegram.sendBotSearchCommand(config: config, query: query)
        }
    }

    func openBotSearch(using config: SearchBotConfig) async {
        botSearchRefreshTask?.cancel()
        botSearchOperationID = nil
        botSearchConversationStartID = nil
        activeBotSearchConfig = config
        botSearchMessages = []
        botSearchError = nil
        isBotSearching = true
        showBotSearch = true

        #if DEBUG
        if isDemo {
            isBotSearching = false
            return
        }
        #endif

        do {
            let history = try await telegram.botSearchHistory(config: config)
            guard activeBotSearchConfig?.id == config.id else { return }
            botSearchMessages = Array(history.suffix(40))
            install(botSearchMessages.compactMap(\.track))
        } catch {
            guard activeBotSearchConfig?.id == config.id else { return }
            botSearchError = UserFacingError.message(for: error)
        }
        if activeBotSearchConfig?.id == config.id {
            isBotSearching = false
        }
    }

    func sendBotSearchMessage(_ text: String) async {
        guard !isBotSearching else { return }
        guard let config = activeBotSearchConfig else { return }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        #if DEBUG
        if isDemo {
            await sendDemoBotSearchMessage(message)
            return
        }
        #endif
        await performBotSearch {
            try await telegram.sendBotMessage(message, to: config)
        }
    }

    func activateBotSearchButton(_ button: BotSearchButton) async {
        guard !isBotSearching else { return }
        guard let config = activeBotSearchConfig else { return }
        guard button.action != .unsupported else {
            botSearchError = "This Telegram button is not supported in Telisten."
            return
        }
        #if DEBUG
        if isDemo {
            await activateDemoBotSearchButton(button)
            return
        }
        #endif
        await performBotSearch {
            try await telegram.pressBotButton(button, for: config)
        }
    }

    func playBotSearchTrack(_ track: Track) {
        let botTracks = botSearchMessages.compactMap(\.track)
        install(botTracks)
        play(track, from: botTracks.isEmpty ? [track] : botTracks)
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

    var listenTogetherChats: [MusicChat] {
        allChats
            .filter { $0.kind != .user && $0.isAdmin == true }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned == true }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func listenTogetherInviteLink(for chat: MusicChat) async throws -> URL {
        let key = "\(activeAccountID ?? "local"):\(chat.id)"
        if let cached = listenTogetherInviteLinks[key] { return cached }
        let link = try await telegram.listenTogetherInviteLink(for: chat)
        listenTogetherInviteLinks[key] = link
        return link
    }

    func listenTogetherContacts() async throws -> [MusicChat] {
        #if DEBUG
        if isDemo {
            return [
                MusicChat(
                    id: "u:3101", peerID: 3101, accessHash: 1, kind: .user,
                    title: "Aiko", username: "aiko"
                ),
                MusicChat(
                    id: "u:3102", peerID: 3102, accessHash: 1, kind: .user,
                    title: "Mika", username: "mika_music"
                ),
                MusicChat(
                    id: "u:3103", peerID: 3103, accessHash: 1, kind: .user,
                    title: "Ren", username: nil
                )
            ]
        }
        #endif
        return try await telegram.telegramContacts()
    }

    func inviteContacts(_ contacts: [MusicChat], to session: ListenTogetherSession) async throws -> Int {
        #if DEBUG
        if isDemo { return contacts.count }
        #endif
        return try await telegram.inviteContacts(contacts, to: session.chat, call: session.call)
    }

    func startListenTogether(in chat: MusicChat) async {
        guard let track = player.track else {
            errorMessage = "Play a track before starting Listen Together."
            return
        }
        await stopListenTogether(endHostedCall: true)
        listenTogetherState = .preparing
        var createdCall: GroupCallReference?
        do {
            let fileURL = try await cachedFile(for: track)
            let presence = ListenTogetherPresence(
                track: track,
                elapsed: player.currentTime,
                isPlaying: player.isPlaying
            )
            let endpoint = try await telegram.startListenTogether(in: chat, presence: presence)
            createdCall = endpoint.call
            try await listenTogetherBroadcaster.connect(to: endpoint)
            if player.isPlaying {
                await listenTogetherBroadcaster.play(fileURL, from: player.currentTime)
            }
            broadcastTrackID = track.id
            broadcastStartOffset = player.currentTime
            broadcastStartedAt = .now
            broadcastWasPlaying = player.isPlaying
            lastCallTitleUpdate = .now
            listenTogetherState = .live(
                ListenTogetherSession(chat: chat, call: endpoint.call, role: .host, presence: presence)
            )
            startListenTogetherCoordinator()
        } catch {
            if let createdCall { try? await telegram.endListenTogether(createdCall) }
            await listenTogetherBroadcaster.disconnect()
            let message = UserFacingError.message(for: error)
            listenTogetherState = .failed(message)
            errorMessage = message
        }
    }

    func joinListenTogether(in chat: MusicChat) async {
        await stopListenTogether(endHostedCall: true)
        listenTogetherState = .preparing
        do {
            guard let call = try await telegram.activeListenTogether(in: chat) else {
                throw TelegramService.ServiceError.groupCallUnavailable
            }
            let presence = ListenTogetherPresence(telegramTitle: call.title)
            let session = ListenTogetherSession(
                chat: chat,
                call: call,
                role: .listener,
                presence: presence
            )
            listenTogetherState = .live(session)
            listenerMetadataTitle = call.title
            listenerMetadataObservedAt = .now
            if let presence { try await synchronizeListener(to: presence) }
            startListenTogetherCoordinator()
        } catch {
            let message = UserFacingError.message(for: error)
            listenTogetherState = .failed(message)
            errorMessage = message
        }
    }

    func stopListenTogether(endHostedCall: Bool = true) async {
        listenTogetherTask?.cancel()
        listenTogetherTask = nil
        if endHostedCall,
           case let .live(session) = listenTogetherState,
           session.role == .host {
            try? await telegram.endListenTogether(session.call)
        }
        await listenTogetherBroadcaster.disconnect()
        listenTogetherState = .idle
        resetListenTogetherRuntime()
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
            guard let chat = await musicSource(for: track) else {
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
        guard let source = await musicSource(for: track) else {
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
        guard let source = await musicSource(for: track) else {
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-no-lyrics") {
            lyricsCandidates = []
            lyricsState = .unavailable
            return
        }
        #endif
        if case let .loaded(value) = lyricsState, value.trackID == track.id { return }
        lyricsState = .loading
        do {
            let sourceChat = allChats.first(where: { $0.id == track.chatID })
            let attachedLRC: [AttachedLRC]
            #if DEBUG
            if isDemo {
                attachedLRC = []
            } else {
                attachedLRC = (try? await telegram.attachedLyrics(for: track, in: sourceChat)) ?? []
            }
            #else
            attachedLRC = (try? await telegram.attachedLyrics(for: track, in: sourceChat)) ?? []
            #endif
            let result = try await lyrics.lyrics(for: track, attachedLRC: attachedLRC)
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
        guard let chat = await musicSource(for: track) else {
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

        guard let chat = await musicSource(for: track) else {
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

    func isDownloadingAll(in playlist: MusicChat) -> Bool {
        downloadingPlaylistIDs.contains(playlist.id)
    }

    func downloadAll(in playlist: MusicChat) {
        guard isPlaylist(playlist), !isDownloadingAll(in: playlist) else { return }
        let playlistID = playlist.id
        downloadingPlaylistIDs.insert(playlistID)
        Task { [weak self] in
            guard let self else { return }
            defer { downloadingPlaylistIDs.remove(playlistID) }

            // Playlists are paged, so resolve the remainder before starting the
            // batch. The existing cached mirror makes this instant offline.
            if selectedChat?.id == playlistID {
                while hasMoreTracks, selectedChat?.id == playlistID {
                    let previousCount = tracks.count
                    let previousOffset = trackSearchOffsetID
                    await loadMoreTracks()
                    if tracks.count == previousCount,
                       trackSearchOffsetID == previousOffset {
                        break
                    }
                }
            }

            let values = arranged(cachedTracks(in: playlist), in: playlist)
            guard !values.isEmpty else { return }
            var failedCount = 0
            for track in values where !cachedIDs.contains(track.id) {
                do {
                    _ = try await cachedFile(for: track)
                } catch is CancellationError {
                    return
                } catch {
                    failedCount += 1
                }
            }
            if failedCount > 0 {
                errorMessage = failedCount == 1
                    ? "One track could not be downloaded."
                    : "\(failedCount) tracks could not be downloaded."
            }
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

    func setLyricsServerURL(_ serverURL: URL) async {
        lyricsServerURL = serverURL
        UserDefaults.standard.set(serverURL.absoluteString, forKey: Self.lyricsServerDefaultsKey)
        await lyrics.setServerURL(serverURL)
        lyricsState = .idle
        lyricsCandidates = []
        if let track = player.track {
            Task { await loadLyrics(for: track) }
        }
    }

    /// Adds a new bot configuration or replaces the configuration with the same ID.
    /// Returns a user-facing validation/persistence error, or `nil` on success.
    @discardableResult
    func upsertSearchBot(_ config: SearchBotConfig) -> String? {
        guard let normalized = normalizedSearchBot(config) else {
            return "Enter a valid Telegram bot username ending in “bot”."
        }
        guard !normalized.searchPrefix.contains(where: \.isNewline),
              !normalized.searchSuffix.contains(where: \.isNewline) else {
            return "Search prefix and suffix must each be a single line."
        }
        guard normalized.searchPrefix.count <= 256, normalized.searchSuffix.count <= 256 else {
            return "Search prefix and suffix must each be 256 characters or fewer."
        }
        let duplicate = searchBots.contains {
            $0.id != normalized.id
                && $0.normalizedBotName.caseInsensitiveCompare(normalized.normalizedBotName) == .orderedSame
                && $0.searchPrefix == normalized.searchPrefix
                && $0.searchSuffix == normalized.searchSuffix
        }
        guard !duplicate else { return "This bot search is already configured." }

        let previous = searchBots
        if let index = searchBots.firstIndex(where: { $0.id == normalized.id }) {
            searchBots[index] = normalized
        } else {
            searchBots.append(normalized)
        }
        guard keychain.saveSearchBotConfigs(searchBots) else {
            searchBots = previous
            return "Telisten couldn’t save this bot search to Keychain."
        }
        return nil
    }

    func deleteSearchBot(id: UUID) {
        let previous = searchBots
        searchBots.removeAll { $0.id == id }
        guard keychain.saveSearchBotConfigs(searchBots) else {
            searchBots = previous
            errorMessage = "Telisten couldn’t update bot searches in Keychain."
            return
        }
    }

    func moveSearchBots(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let source = offsets.sorted()
        guard !source.isEmpty, source.allSatisfy(searchBots.indices.contains) else { return }
        let previous = searchBots
        let moving = source.map { searchBots[$0] }
        for index in source.reversed() { searchBots.remove(at: index) }
        let removedBeforeDestination = source.lazy.filter { $0 < destination }.count
        let insertionIndex = max(0, min(searchBots.count, destination - removedBeforeDestination))
        searchBots.insert(contentsOf: moving, at: insertionIndex)
        guard keychain.saveSearchBotConfigs(searchBots) else {
            searchBots = previous
            errorMessage = "Telisten couldn’t update bot searches in Keychain."
            return
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
        downloads[track.id] = DownloadStatus(
            progress: downloads[track.id]?.progress ?? 0,
            isCached: false,
            isDownloading: true
        )
        persistLibrary()
        let cache = cache
        let transfer = await progressiveTransfer(for: track)
        let task = Task<URL, Error> {
            let temporary = await cache.partialLocation(for: track).dataURL
            try await transfer.downloadAll { [weak self] value in
                let bytes = await cache.totalBytes()
                await MainActor.run {
                    self?.downloads[track.id] = DownloadStatus(
                        progress: value,
                        isCached: false,
                        isDownloading: true
                    )
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
            downloads[track.id] = DownloadStatus(
                progress: downloads[track.id]?.progress ?? 0,
                isCached: false,
                isDownloading: false
            )
            throw error
        }
    }

    private func progressiveTransfer(for track: Track) async -> ProgressiveAudioTransfer {
        if let transfer = activeTransfers[track.id] { return transfer }
        let location = await cache.partialLocation(for: track)
        let telegram = telegram
        let sourceChat = await musicSource(for: track)
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

    private func musicSource(for track: Track) async -> MusicChat? {
        if let chat = allChats.first(where: { $0.id == track.chatID }) { return chat }
        if let selectedChat, selectedChat.id == track.chatID { return selectedChat }
        if let bot = await telegram.cachedSearchBot(chatID: track.chatID) { return bot }

        for config in searchBots {
            guard let bot = try? await telegram.searchBotChat(config) else { continue }
            if bot.id == track.chatID { return bot }
        }
        return nil
    }

    private func startListenTogetherCoordinator() {
        listenTogetherTask?.cancel()
        listenTogetherTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                switch self.listenTogetherState {
                case let .live(session) where session.role == .host:
                    await self.synchronizeHost(session)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                case let .live(session) where session.role == .listener:
                    await self.refreshListener(session)
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                default:
                    return
                }
            }
        }
    }

    private func synchronizeHost(_ existingSession: ListenTogetherSession) async {
        guard let track = player.track else { return }
        var session = existingSession
        var forceTitleUpdate = false

        if let streamError = await listenTogetherBroadcaster.consumeError() {
            errorMessage = streamError
        }

        do {
            if broadcastTrackID != track.id {
                let fileURL = try await cachedFile(for: track)
                if player.isPlaying {
                    await listenTogetherBroadcaster.play(fileURL, from: player.currentTime)
                } else {
                    await listenTogetherBroadcaster.pause()
                }
                broadcastTrackID = track.id
                broadcastStartOffset = player.currentTime
                broadcastStartedAt = .now
                broadcastWasPlaying = player.isPlaying
                forceTitleUpdate = true
            } else if broadcastWasPlaying != player.isPlaying {
                if player.isPlaying, let fileURL = await cache.localURL(for: track) {
                    await listenTogetherBroadcaster.play(fileURL, from: player.currentTime)
                    broadcastStartOffset = player.currentTime
                    broadcastStartedAt = .now
                } else {
                    await listenTogetherBroadcaster.pause()
                }
                broadcastWasPlaying = player.isPlaying
                forceTitleUpdate = true
            } else if player.isPlaying, let startedAt = broadcastStartedAt {
                let expected = broadcastStartOffset + Date.now.timeIntervalSince(startedAt)
                if abs(expected - player.currentTime) > 2.5,
                   let fileURL = await cache.localURL(for: track) {
                    await listenTogetherBroadcaster.play(fileURL, from: player.currentTime)
                    broadcastStartOffset = player.currentTime
                    broadcastStartedAt = .now
                    forceTitleUpdate = true
                }
            }

            let presence = ListenTogetherPresence(
                track: track,
                elapsed: player.currentTime,
                isPlaying: player.isPlaying
            )
            let shouldUpdateTitle = forceTitleUpdate
                || lastCallTitleUpdate == nil
                || Date.now.timeIntervalSince(lastCallTitleUpdate ?? .distantPast) >= 12
            if shouldUpdateTitle {
                try await telegram.updateListenTogetherTitle(
                    session.call,
                    title: presence.telegramTitle
                )
                session.call.title = presence.telegramTitle
                lastCallTitleUpdate = .now
            }
            session.presence = presence
            listenTogetherState = .live(session)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func refreshListener(_ existingSession: ListenTogetherSession) async {
        do {
            guard let call = try await telegram.refreshListenTogether(existingSession.call) else {
                listenTogetherState = .failed("This Listen Together session has ended.")
                listenTogetherTask?.cancel()
                return
            }
            if listenerMetadataTitle != call.title {
                listenerMetadataTitle = call.title
                listenerMetadataObservedAt = .now
            }
            guard var presence = ListenTogetherPresence(telegramTitle: call.title) else {
                throw TelegramService.ServiceError.groupCallUnavailable
            }
            if presence.isPlaying, let observedAt = listenerMetadataObservedAt {
                presence.elapsed = min(
                    presence.duration,
                    presence.elapsed + Date.now.timeIntervalSince(observedAt)
                )
            }
            try await synchronizeListener(to: presence)
            listenTogetherState = .live(
                ListenTogetherSession(
                    chat: existingSession.chat,
                    call: call,
                    role: .listener,
                    presence: presence
                )
            )
        } catch {
            let message = UserFacingError.message(for: error)
            listenTogetherState = .failed(message)
            errorMessage = message
            listenTogetherTask?.cancel()
        }
    }

    private func synchronizeListener(to presence: ListenTogetherPresence) async throws {
        let track: Track
        if let current = player.track, listenTogetherMatchScore(current, presence: presence) < 20 {
            track = current
        } else {
            var candidates = Array(knownTracks.values) + tracks + queue
            #if DEBUG
            if !isDemo {
                let query = presence.title.replacingOccurrences(of: "_", with: " ")
                candidates += try await telegram.searchAllMusic(query: query)
            }
            #else
            let query = presence.title.replacingOccurrences(of: "_", with: " ")
            candidates += try await telegram.searchAllMusic(query: query)
            #endif
            let unique = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard let match = unique.values.min(by: {
                listenTogetherMatchScore($0, presence: presence)
                    < listenTogetherMatchScore($1, presence: presence)
            }), listenTogetherMatchScore(match, presence: presence) < 70 else {
                throw TelegramService.ServiceError.groupCallUnavailable
            }
            track = match
        }

        if player.track?.id != track.id {
            play(track, from: [track])
            for _ in 0..<80 {
                guard player.track?.id == track.id, player.isLoading else { break }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        guard player.track?.id == track.id else { return }
        if abs(player.currentTime - presence.elapsed) > 2.5 {
            player.seek(to: presence.elapsed)
        }
        if presence.isPlaying {
            if !player.isPlaying, !player.isLoading { player.play() }
        } else if player.isPlaying || player.isLoading {
            player.pause()
        }
    }

    private func listenTogetherMatchScore(_ track: Track, presence: ListenTogetherPresence) -> Double {
        let targetTitle = normalizedListenTogetherText(presence.title)
        let candidateTitle = normalizedListenTogetherText(track.displayTitle)
        let titlePenalty: Double
        if targetTitle == candidateTitle {
            titlePenalty = 0
        } else if targetTitle.contains(candidateTitle) || candidateTitle.contains(targetTitle) {
            titlePenalty = 12
        } else {
            let targetWords = Set(targetTitle.split(separator: " "))
            let candidateWords = Set(candidateTitle.split(separator: " "))
            let overlap = targetWords.intersection(candidateWords).count
            titlePenalty = overlap > 0 ? 38 : 100
        }
        let durationPenalty = min(abs(track.duration - presence.duration), 30)
        let artistPenalty = normalizedListenTogetherText(track.displayArtist)
            == normalizedListenTogetherText(presence.artist) ? 0.0 : 3.0
        return titlePenalty + durationPenalty + artistPenalty
    }

    private func normalizedListenTogetherText(_ value: String) -> String {
        let expanded = value.replacingOccurrences(of: "_", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        return expanded.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func resetListenTogetherRuntime() {
        broadcastTrackID = nil
        broadcastStartedAt = nil
        broadcastStartOffset = 0
        broadcastWasPlaying = false
        lastCallTitleUpdate = nil
        listenerMetadataTitle = nil
        listenerMetadataObservedAt = nil
    }

    private func completeLogin(profile: TelegramAccount) async throws {
        do {
            try await finishLogin(profile: profile)
        } catch {
            await recoverFromFailedFreshSessionCommit(error)
            throw error
        }
    }

    private func finishLogin(profile initialProfile: TelegramAccount) async throws {
        phase = .connecting
        if activeAccountID == nil {
            activeAccountID = "legacy"
        }
        var profile = initialProfile
        if let replacement = accounts.first(where: {
            $0.userID == profile.userID && $0.id != profile.id
        }) {
            try await telegram.replaceCurrentSession(withAccountID: replacement.id)
            activeAccountID = replacement.id
            profile.id = replacement.id
            // The temporary authorization slot intentionally starts empty. Once
            // it replaces an existing account, restore that account's local
            // queues, favorites, playlist mirrors and known tracks before any
            // network refresh can persist over them.
            restoreLibrary()
            accounts.removeAll { $0.id != replacement.id && $0.userID == profile.userID }
        }
        if let index = accounts.firstIndex(where: { $0.id == profile.id }) {
            accounts[index] = profile
        } else {
            accounts.append(profile)
        }
        isAddingAccount = false
        previousAccountID = nil
        persistAccounts()
        phase = .ready
        errorMessage = nil
        let committedAccountID = profile.id
        postLoginRefreshTask?.cancel()
        postLoginRefreshTask = Task { [weak self] in
            await self?.refreshAfterLogin(profile: profile, accountID: committedAccountID)
        }
    }

    private func refreshAfterLogin(profile: TelegramAccount, accountID: String) async {
        await loadAvatar(for: profile)
        guard !Task.isCancelled, activeAccountID == accountID else { return }
        do {
            let loadedChats = try await telegram.loadChats()
            guard !Task.isCancelled, activeAccountID == accountID else { return }
            allChats = mergedChats(loadedChats, with: playlists)
            applyMusicChatIndex()
            await refreshPlaylists(expectedAccountID: accountID)
            guard !Task.isCancelled, activeAccountID == accountID else { return }
            beginMusicChatIndexing()
        } catch is CancellationError {
            return
        } catch {
            // Authorization and local account commit already succeeded. Keep
            // the offline library open and retry Telegram content later.
            guard activeAccountID == accountID else { return }
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func recoverFromFailedFreshSessionCommit(_ error: Error) async {
        let accountToRestore = previousAccountID
        await telegram.discardSession()
        passwordRequestedByQRCode = false
        isAddingAccount = false
        activeAccountID = accountToRestore
        previousAccountID = nil
        if let accountToRestore {
            await activateAccount(accountToRestore)
        } else {
            resetForAccountTransition()
            phase = .signedOut
        }
        errorMessage = UserFacingError.message(for: error)
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
            if UserFacingError.isExpiredTelegramSession(error) {
                phase = .signedOut
                errorMessage = UserFacingError.message(for: error)
            } else {
                phase = canOpenLibrary ? .ready : .signedOut
                if !canOpenLibrary {
                    errorMessage = UserFacingError.message(for: error)
                }
            }
        }
    }

    private func resetForAccountTransition() {
        postLoginRefreshTask?.cancel()
        postLoginRefreshTask = nil
        musicChatIndexTask?.cancel()
        listenTogetherTask?.cancel()
        listenTogetherTask = nil
        Task { await listenTogetherBroadcaster.disconnect() }
        listenTogetherState = .idle
        showListenTogetherSheet = false
        resetListenTogetherRuntime()
        player.reset()
        allChats = []
        chats = []
        savedChatIDs = []
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
        listenTogetherInviteLinks = [:]
        botSearchOperationID = nil
        botSearchRefreshTask?.cancel()
        botSearchRefreshTask = nil
        botSearchConversationStartID = nil
        activeBotSearchConfig = nil
        botSearchMessages = []
        botSearchError = nil
        isBotSearching = false
        showBotSearch = false
        currentQueueIndex = nil
    }

    private func performBotSearch(
        startingWith initialCommand: String? = nil,
        operation: () async throws -> [BotSearchMessage]
    ) async {
        let operationID = UUID()
        botSearchRefreshTask?.cancel()
        botSearchOperationID = operationID
        isBotSearching = true
        botSearchError = nil
        startBotSearchRefresh(
            operationID: operationID,
            initialCommand: initialCommand
        )
        defer {
            if botSearchOperationID == operationID {
                isBotSearching = false
            }
        }

        do {
            let values = try await operation()
            guard botSearchOperationID == operationID else { return }
            _ = applyBotSearchSnapshot(
                values,
                initialCommand: initialCommand,
                operationID: operationID
            )
        } catch is CancellationError {
            // A newer bot action or account switch superseded this request.
        } catch {
            guard botSearchOperationID == operationID else { return }
            botSearchError = UserFacingError.message(for: error)
        }
    }

    private func startBotSearchRefresh(
        operationID: UUID,
        initialCommand: String?
    ) {
        guard let config = activeBotSearchConfig else { return }
        botSearchRefreshTask = Task { [weak self] in
            guard let self else { return }
            var sawIncomingResponse = false
            var stableReadsAfterResponse = 0

            // Bot replies are frequently created and then edited in place. Keep
            // refreshing long enough to render those streamed edits, while using
            // a slower tail so an unusually slow bot does not hammer Telegram.
            for attempt in 0..<75 {
                if Task.isCancelled || botSearchOperationID != operationID { return }
                let delay: Duration = attempt < 20 ? .milliseconds(750) : .seconds(2)
                try? await Task.sleep(for: delay)
                if Task.isCancelled || botSearchOperationID != operationID { return }

                do {
                    let values = try await telegram.botSearchHistory(config: config)
                    let changed = applyBotSearchSnapshot(
                        values,
                        initialCommand: initialCommand,
                        operationID: operationID
                    )
                    let hasIncoming = botSearchMessages.contains { !$0.isOutgoing }
                    sawIncomingResponse = sawIncomingResponse || hasIncoming
                    if sawIncomingResponse {
                        stableReadsAfterResponse = changed ? 0 : stableReadsAfterResponse + 1
                        if stableReadsAfterResponse >= 10 { return }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // The foreground operation reports actionable failures. A
                    // transient refresh failure should not erase a reply already
                    // on screen; the next bounded poll can recover the stream.
                    continue
                }
            }
        }
    }

    @discardableResult
    private func applyBotSearchSnapshot(
        _ values: [BotSearchMessage],
        initialCommand: String?,
        operationID: UUID
    ) -> Bool {
        guard botSearchOperationID == operationID else { return false }
        if botSearchConversationStartID == nil,
           let initialCommand,
           let sent = values.last(where: {
               $0.isOutgoing
                   && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == initialCommand
           }) {
            botSearchConversationStartID = sent.id
        }

        let scoped: [BotSearchMessage]
        if let startID = botSearchConversationStartID {
            scoped = values.filter { $0.id >= startID }
        } else if initialCommand != nil {
            // Do not flash an older conversation while Telegram is committing
            // the newly sent command to history.
            scoped = []
        } else {
            scoped = Array(values.suffix(40))
        }
        guard scoped != botSearchMessages else { return false }
        botSearchMessages = scoped
        if scoped.contains(where: { !$0.isOutgoing }) {
            botSearchError = nil
        }
        install(scoped.compactMap(\.track))
        return true
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
        case let .ready(profile):
            try await completeLogin(profile: profile)
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

    private func refreshPlaylists(expectedAccountID: String? = nil) async {
        if let values = try? await telegram.loadPlaylistChats(from: allChats) {
            if let expectedAccountID, activeAccountID != expectedAccountID { return }
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
                let hasMusic = try await telegram.hasMusic(in: chat)
                musicChatIndex[chat.id] = MusicChatIndexEntry(
                    hasMusic: hasMusic,
                    checkedAt: .now
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
        musicChatIndex[chat.id] = MusicChatIndexEntry(
            hasMusic: true,
            checkedAt: .now
        )
        persistMusicChatIndex()
        applyMusicChatIndex()
    }

    private func applyMusicChatIndex() {
        let validIDs = Set(allChats.map(\.id))
        musicChatIndex = musicChatIndex.filter { validIDs.contains($0.key) }
        chats = allChats.filter { musicChatIndex[$0.id]?.hasMusic == true }
    }

    private func resetTrackDetails(ifChangingTo track: Track) {
        guard player.track?.id != track.id else { return }
        lyricsState = .idle
        lyricsCandidates = []
        commentsState = .idle
        commentsTrackID = nil
    }

    #if DEBUG
    private func loadDemoBotSearch(
        config: SearchBotConfig,
        query: String,
        command: String
    ) async {
        isBotSearching = true
        botSearchError = nil
        try? await Task.sleep(nanoseconds: 220_000_000)

        let sentAt = Date.now.addingTimeInterval(-0.4)
        let resultButtons = (1...8).map { number in
            BotSearchButton(
                id: "demo-result-\(number)",
                title: String(number),
                action: .sendText(String(number))
            )
        }
        func textButton(_ title: String) -> BotSearchButton {
            BotSearchButton(
                id: "demo-action-\(title)",
                title: title,
                action: .sendText(title)
            )
        }

        botSearchConversationStartID = 70_001
        botSearchMessages = [
            BotSearchMessage(
                id: 70_001,
                isOutgoing: true,
                text: command,
                date: sentAt,
                buttonRows: [],
                track: nil
            ),
            BotSearchMessage(
                id: 70_002,
                isOutgoing: false,
                text: """
                🎵 NetEase Cloud Music search results
                Tap a number below to pick a track

                Keyword: \(query)
                Page 1/6

                1. 花鳥風月 — SEKAI NO OWARI
                2. Stella — SEKAI NO OWARI
                3. Never Ending World — SEKAI NO OWARI
                4. スターライトパレード — SEKAI NO OWARI
                5. 深海魚 — SEKAI NO OWARI
                6. Dragon Night — SEKAI NO OWARI
                7. 夜桜 — SEKAI NO OWARI
                8. Stella — SEKAI NO OWARI
                """,
                date: .now,
                buttonRows: [
                    resultButtons,
                    [textButton("Close"), textButton("Next")],
                    [textButton("Apple"), textButton("Bilibili"), textButton("KuGou")],
                    [textButton("KuWo"), textButton("NetEase"), textButton("QQ Music")],
                    [textButton("Soda"), textButton("Spotify"), textButton("YouTube")]
                ],
                track: nil
            )
        ]
        isBotSearching = false
    }

    private func sendDemoBotSearchMessage(_ text: String) async {
        isBotSearching = true
        botSearchError = nil
        let nextID = (botSearchMessages.map(\.id).max() ?? 70_000) + 1
        botSearchMessages.append(
            BotSearchMessage(
                id: nextID,
                isOutgoing: true,
                text: text,
                date: .now,
                buttonRows: [],
                track: nil
            )
        )
        try? await Task.sleep(nanoseconds: 180_000_000)
        botSearchMessages.append(
            BotSearchMessage(
                id: nextID + 1,
                isOutgoing: false,
                text: "Choose one of the search-result buttons above.",
                date: .now,
                buttonRows: [],
                track: nil
            )
        )
        isBotSearching = false
    }

    private func activateDemoBotSearchButton(_ button: BotSearchButton) async {
        let text: String
        switch button.action {
        case let .sendText(value): text = value
        case .callback: text = button.title
        case .openURL, .unsupported: return
        }

        isBotSearching = true
        botSearchError = nil
        let nextID = (botSearchMessages.map(\.id).max() ?? 70_000) + 1
        botSearchMessages.append(
            BotSearchMessage(
                id: nextID,
                isOutgoing: true,
                text: text,
                date: .now,
                buttonRows: [],
                track: nil
            )
        )
        try? await Task.sleep(nanoseconds: 220_000_000)

        if Int(text) != nil {
            let result = Track(
                documentID: 88_001,
                accessHash: 1,
                fileReference: Data(),
                dcID: 2,
                messageID: nextID + 1,
                chatID: "u:DemoMusicBot",
                title: "花鳥風月",
                artist: "SEKAI NO OWARI",
                fileName: "花鳥風月 - SEKAI NO OWARI.flac",
                mimeType: "audio/flac",
                duration: 277,
                size: 31_190_000,
                date: .now
            )
            botSearchMessages.append(
                BotSearchMessage(
                    id: nextID + 1,
                    isOutgoing: false,
                    text: "31.19 MB  ·  Lossless FLAC\nvia @DemoMusicBot",
                    date: .now,
                    buttonRows: [],
                    track: result
                )
            )
            install([result])
        } else {
            botSearchMessages.append(
                BotSearchMessage(
                    id: nextID + 1,
                    isOutgoing: false,
                    text: text == "Next" ? "Page 2/6" : "Search source: \(text)",
                    date: .now,
                    buttonRows: [],
                    track: nil
                )
            )
        }
        isBotSearching = false
    }

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
            isPinned: true,
            isAdmin: true,
            canInviteUsers: true,
            canManageCalls: true
        )
        let discoveries = MusicChat(
            id: "g:1002",
            peerID: 1002,
            accessHash: nil,
            kind: .group,
            title: "Music Discoveries",
            username: nil,
            isAdmin: true,
            canInviteUsers: true,
            canManageCalls: true
        )
        let playlist = MusicChat(
            id: "c:2001",
            peerID: 2001,
            accessHash: 1,
            kind: .channel,
            title: "Sunday Drive",
            username: nil,
            isAdmin: true,
            canInviteUsers: true,
            canManageCalls: true
        )
        chats = [source, discoveries, playlist]
        allChats = chats
        playlists = [playlist]
        savedChatIDs = [source.id]
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
        if arguments.contains("--demo-listen-together-live") {
            listenTogetherState = .live(
                ListenTogetherSession(
                    chat: source,
                    call: GroupCallReference(
                        id: 5001,
                        accessHash: 1,
                        title: "♫ The Chain — Fleetwood Mac · 0:48/4:31",
                        participantCount: 4
                    ),
                    role: .host,
                    presence: ListenTogetherPresence(
                        track: sampleTracks[0],
                        elapsed: 48,
                        isPlaying: true
                    )
                )
            )
            showListenTogetherSheet = true
        } else if arguments.contains("--demo-listen-together") {
            showListenTogetherSheet = true
        }
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

    private func restoreSearchBots() {
        let defaults = UserDefaults.standard
        let migrationKey = "searchBots.removedBuiltInDefault"
        var stored = keychain.loadSearchBotConfigs() ?? []

        // Older builds seeded Music163DownBot and synchronized it as if
        // the user had configured it. Remove that one legacy seed exactly once;
        // all bot configurations are now explicit user additions.
        if !defaults.bool(forKey: migrationKey) {
            let original = stored
            stored.removeAll {
                $0.normalizedBotName.caseInsensitiveCompare("Music163DownBot") == .orderedSame
                    && $0.searchPrefix.isEmpty
                    && $0.searchSuffix.isEmpty
            }
            defaults.set(true, forKey: migrationKey)
            if stored != original {
                _ = keychain.saveSearchBotConfigs(stored)
            }
        }

        var seen: Set<String> = []
        searchBots = stored.compactMap { config in
            guard let normalized = normalizedSearchBot(config),
                  !normalized.searchPrefix.contains(where: \.isNewline),
                  !normalized.searchSuffix.contains(where: \.isNewline) else { return nil }
            let identity = [
                normalized.normalizedBotName.lowercased(),
                normalized.searchPrefix,
                normalized.searchSuffix
            ].joined(separator: "\u{1F}")
            return seen.insert(identity).inserted ? normalized : nil
        }
        if searchBots != stored {
            _ = keychain.saveSearchBotConfigs(searchBots)
        }
    }

    private func normalizedSearchBot(_ config: SearchBotConfig) -> SearchBotConfig? {
        var username = config.botName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = username.range(of: "https://t.me/", options: [.anchored, .caseInsensitive]) {
            username.removeSubrange(range)
        } else if let range = username.range(of: "t.me/", options: [.anchored, .caseInsensitive]) {
            username.removeSubrange(range)
        }
        while username.hasPrefix("@") { username.removeFirst() }
        username = String(username.prefix { $0 != "/" && !$0.isWhitespace })

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard (5...32).contains(username.count),
              username.lowercased().hasSuffix("bot"),
              username.unicodeScalars.allSatisfy(allowed.contains) else { return nil }

        return SearchBotConfig(
            id: config.id,
            botName: username,
            searchPrefix: config.searchPrefix,
            searchSuffix: config.searchSuffix
        )
    }

    private func restoreAccounts() {
        let defaults = UserDefaults.standard
        let localAccounts = defaults.data(forKey: "telegram.accounts")
            .flatMap { try? JSONDecoder().decode([TelegramAccount].self, from: $0) }
            ?? []
        let localActiveID = defaults.string(forKey: "telegram.activeAccountID")
        let registry = keychain.loadAccountRegistry()
        let hasMigratedRegistry = defaults.bool(forKey: "telegram.accounts.keychainMigrated")
        let storedSessionAccountIDs = keychain.availableSessionAccountIDs()

        if let registry, hasMigratedRegistry {
            accounts = registry.accounts
        } else if let registry {
            var merged = localAccounts
            var knownIDs = Set(merged.map(\.id))
            for account in registry.accounts where knownIDs.insert(account.id).inserted {
                merged.append(account)
            }
            accounts = merged
        } else {
            accounts = localAccounts
        }

        for accountID in storedSessionAccountIDs where !accounts.contains(where: { $0.id == accountID }) {
            accounts.append(TelegramAccount(
                id: accountID,
                userID: 0,
                displayName: "Telegram Account",
                username: nil
            ))
        }
        if !accounts.contains(where: { $0.id == "legacy" }),
           accounts.isEmpty && defaults.bool(forKey: "telegram.authorized") {
            accounts.append(TelegramAccount(
                id: "legacy",
                userID: 0,
                displayName: "Telegram Account",
                username: nil
            ))
        }
        let preferredIDs = hasMigratedRegistry
            ? [registry?.activeAccountID, localActiveID]
            : [localActiveID, registry?.activeAccountID]
        activeAccountID = preferredIDs
            .compactMap { $0 }
            .first { candidate in accounts.contains { $0.id == candidate } }
            ?? accounts.first?.id
        persistAccounts()
    }

    private func sessionRestoreCandidateIDs() -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in [activeAccountID].compactMap({ $0 }) + accounts.map(\.id) + ["legacy"]
            where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private func persistAccounts() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(accounts), forKey: "telegram.accounts")
        if let activeAccountID {
            defaults.set(activeAccountID, forKey: "telegram.activeAccountID")
        } else {
            defaults.removeObject(forKey: "telegram.activeAccountID")
        }
        if keychain.saveAccountRegistry(accounts: accounts, activeAccountID: activeAccountID) {
            defaults.set(true, forKey: "telegram.accounts.keychainMigrated")
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
        savedChatIDs = Set(
            defaults.stringArray(forKey: accountStorageKey("library.savedChats")) ?? []
        )
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
        persistSavedChats()
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

    private func persistSavedChats() {
        UserDefaults.standard.set(
            Array(savedChatIDs),
            forKey: accountStorageKey("library.savedChats")
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
