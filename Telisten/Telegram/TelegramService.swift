import Foundation
import MTProtoClientKit
import NIOMTProtoEncryption

private enum FileRequestPriority {
    case playback
    case background
}

private actor FileRequestGate {
    private struct Waiter {
        var priority: FileRequestPriority
        var continuation: CheckedContinuation<Void, Never>
    }

    private var isBusy = false
    private var waiters: [Waiter] = []

    func enter(priority: FileRequestPriority) async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(priority: priority, continuation: continuation))
        }
    }

    func leave() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            let nextIndex = waiters.firstIndex { $0.priority == .playback } ?? waiters.startIndex
            waiters.remove(at: nextIndex).continuation.resume()
        }
    }
}

actor TelegramService {
    enum RequestCodeResult: Sendable {
        case code(hint: String, isEmail: Bool)
        case emailSetup
        case password(hint: String)
        case ready
    }

    enum SignInResult: Sendable {
        case ready
        case password(hint: String)
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidAPIID
        case invalidCodeResponse
        case paidAuthorizationRequired(String)
        case signUpRequired
        case noConnection
        case downloadRedirect
        case incompleteDownload
        case expiredFileReference
        case playlistCreationFailed
        case playlistFolderFailed
        case playlistDeletionUnavailable
        case playlistTrackDeletionUnavailable
        case playlistRenameUnavailable
        case commentingUnavailable
        case invalidPhoneNumber
        case invalidEmailAddress
        case emptyLoginCode
        case sessionPersistenceFailed
        case telegram(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Add the Telegram API credentials to .env and rebuild the app."
            case .invalidAPIID: "The Telegram API credentials in .env are invalid."
            case .invalidCodeResponse: "Telegram returned an unexpected login response."
            case let .paidAuthorizationRequired(email): "Telegram requires paid authorization for this number. Contact \(email)."
            case .signUpRequired: "Create this account in the official Telegram app before signing in here."
            case .noConnection: "The Telegram connection is not ready."
            case .downloadRedirect: "This file requires Telegram CDN handling, which was not negotiated."
            case .incompleteDownload: "The file download ended before all bytes arrived."
            case .expiredFileReference: "Telegram expired this track reference. Telisten could not refresh it automatically."
            case .playlistCreationFailed: "Telegram created no usable playlist chat."
            case .playlistFolderFailed: "Telegram did not accept the _Playlist folder update."
            case .playlistDeletionUnavailable: "Only Telegram channel playlists can be deleted."
            case .playlistTrackDeletionUnavailable: "This playlist entry cannot be deleted."
            case .playlistRenameUnavailable: "This playlist cannot be renamed."
            case .commentingUnavailable: "This Telegram post does not have a discussion where comments can be added."
            case .invalidPhoneNumber: "Enter a valid phone number in international format, including the country code."
            case .invalidEmailAddress: "Enter a valid email address."
            case .emptyLoginCode: "Enter the login code Telegram sent you."
            case .sessionPersistenceFailed: "Telisten could not save the Telegram session in Keychain. Check the app signature and try again."
            case let .telegram(message): message
            }
        }
    }

    private struct Endpoint: Sendable {
        var host: String
        var port: Int
        var mediaOnly: Bool
    }

    private struct ConnectionKey: Hashable, Sendable {
        var dcID: Int32
        var media: Bool
    }

    private struct Connection: Sendable {
        var mtproto: MTProtoClient
        var client: TLClient
    }

    private struct Transport: TLClientTransport {
        let client: MTProtoClient

        func send(_ requestBody: Data) async throws -> Data {
            try await client.invokeRaw(requestBody)
        }
    }

    private static let layer: Int32 = 223
    private static let rsaModuli = [
        "e8bb3305c0b52c6cf2afdf7637313489e63e05268e5badb601af417786472e5f93b85438968e20e6729a301c0afc121bf7151f834436f7fda680847a66bf64accec78ee21c0b316f0edafe2f41908da7bd1f4a5107638eeb67040ace472a14f90d9f7c2b7def99688ba3073adb5750bb02964902a359fe745d8170e36876d4fd8a5d41b2a76cbff9a13267eb9580b2d06d10357448d20d9da2191cb5d8c93982961cdfdeda629e37f1fb09a0722027696032fe61ed663db7a37f6f263d370f69db53a0dc0a1748bdaaff6209d5645485e6e001d1953255757e4b8e42813347b11da6ab500fd0ace7e6dfa3736199ccaf9397ed0745a427dcfa6cd67bcb1acff3",
        "c8c11d635691fac091dd9489aedced2932aa8a0bcefef05fa800892d9b52ed03200865c9e97211cb2ee6c7ae96d3fb0e15aeffd66019b44a08a240cfdd2868a85e1f54d6fa5deaa041f6941ddf302690d61dc476385c2fa655142353cb4e4b59f6e5b6584db76fe8b1370263246c010c93d011014113ebdf987d093f9d37c2be48352d69a1683f8f6e6c2167983c761e3ab169fde5daaa12123fa1beab621e4da5935e9c198f82f35eae583a99386d8110ea6bd1abb0f568759f62694419ea5f69847c43462abef858b4cb5edc84e7b9226cd7bd7e183aa974a712c079dde85b9dc063b8a5c08e8f859c0ee5dcd824c7807f20153361a7f63cfd2a433a1be7f5"
    ]
    private static let seedEndpoints: [Int32: Endpoint] = [
        1: Endpoint(host: "149.154.175.53", port: 443, mediaOnly: false),
        2: Endpoint(host: "149.154.167.51", port: 443, mediaOnly: false),
        3: Endpoint(host: "149.154.175.100", port: 443, mediaOnly: false),
        4: Endpoint(host: "149.154.167.91", port: 443, mediaOnly: false),
        5: Endpoint(host: "91.108.56.130", port: 443, mediaOnly: false)
    ]

    private let keychain: KeychainStore
    private let fileRequestGate = FileRequestGate()
    private var credentials: TelegramCredentials?
    private var accountID: String
    private var primaryDC: Int32
    private var endpoints: [Int32: [Endpoint]] = [:]
    private var endpointCursors: [ConnectionKey: Int] = [:]
    private var connections: [ConnectionKey: Connection] = [:]
    private var authorizedConnections: Set<ConnectionKey> = []
    private var refreshedTracks: [String: Track] = [:]
    private var phoneNumber = ""
    private var phoneCodeHash = ""
    private var pendingCodeIsEmail = false

    init(keychain: KeychainStore) {
        self.keychain = keychain
        let defaults = UserDefaults.standard
        let storedAccountID = defaults.string(forKey: "telegram.activeAccountID") ?? "legacy"
        accountID = storedAccountID
        let primaryKey = "telegram.primaryDC.\(storedAccountID)"
        if defaults.object(forKey: primaryKey) != nil {
            primaryDC = Int32(defaults.integer(forKey: primaryKey))
        } else if storedAccountID == "legacy" {
            primaryDC = Int32(defaults.integer(forKey: "telegram.primaryDC"))
        } else {
            primaryDC = 2
        }
        if primaryDC == 0 { primaryDC = 2 }
    }

    func configure(_ value: TelegramCredentials) throws {
        guard value.apiID > 0, value.apiHash.count == 32 else { throw ServiceError.invalidAPIID }
        credentials = value
    }

    func hasAuthorizedSession() -> Bool {
        guard isAuthorizationSaved, credentials != nil else {
            return false
        }
        guard keychain.loadSession(dcID: primaryDC, accountID: accountID) != nil else {
            setAuthorizationSaved(false)
            return false
        }
        return true
    }

    func useAccount(_ id: String, clearExisting: Bool = false) async {
        for connection in connections.values {
            try? await connection.mtproto.disconnect()
        }
        connections.removeAll()
        authorizedConnections.removeAll()
        refreshedTracks.removeAll()
        accountID = id
        if clearExisting {
            keychain.clearSessions(accountID: id)
            setAuthorizationSaved(false)
        }
        let defaults = UserDefaults.standard
        let key = primaryDCDefaultsKey
        if defaults.object(forKey: key) != nil {
            primaryDC = Int32(defaults.integer(forKey: key))
        } else if id == "legacy" {
            primaryDC = Int32(defaults.integer(forKey: "telegram.primaryDC"))
        } else {
            primaryDC = 2
        }
        if primaryDC == 0 { primaryDC = 2 }
        phoneNumber = ""
        phoneCodeHash = ""
        pendingCodeIsEmail = false
    }

    func restoreSession() async throws -> [MusicChat] {
        guard hasAuthorizedSession() else { return [] }
        _ = try await authorizedConnection(dcID: primaryDC, media: false)
        return try await loadChats()
    }

    func currentAccount() async throws -> TelegramAccount {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        let users = try await connection.client.users.getUsers(
            id: [.inputUserSelf(TL.InputUserSelf())]
        )
        guard case let .user(user)? = users.first else {
            throw ServiceError.invalidCodeResponse
        }
        let fullName = [user.firstName, user.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let avatar: (photoID: Int64, dcID: Int32)? = user.photo.flatMap { photo in
            switch photo {
            case let .userProfilePhoto(value): (value.photoId, value.dcId)
            case .userProfilePhotoEmpty: nil
            }
        }
        return TelegramAccount(
            id: accountID,
            userID: user.id,
            displayName: fullName.isEmpty ? (user.username ?? "Telegram Account") : fullName,
            username: user.username,
            avatarPhotoID: avatar?.photoID,
            avatarDCID: avatar?.dcID
        )
    }

    func sendCode(to phone: String) async throws -> RequestCodeResult {
        let digits = phone.filter(\.isNumber)
        guard (8...15).contains(digits.count) else { throw ServiceError.invalidPhoneNumber }
        phoneNumber = "+" + digits
        do {
            return try handleSentCode(try await sendCodeResponseWithMigration())
        } catch let error as MTProtoRPCError where error.message == "SESSION_PASSWORD_NEEDED" {
            let connection = try await connection(dcID: primaryDC, media: false)
            let password = try await connection.client.account.getPassword()
            return .password(hint: password.hint ?? "")
        } catch {
            throw readableLoginError(error)
        }
    }

    func signIn(code: String) async throws -> SignInResult {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else { throw ServiceError.emptyLoginCode }
        let connection = try await connection(dcID: primaryDC, media: false)
        do {
            let emailVerification: TL.EmailVerificationType? = pendingCodeIsEmail
                ? .emailVerificationCode(TL.EmailVerificationCode(code: cleanCode))
                : nil
            let authorization = try await connection.client.auth.signIn(
                phoneNumber: phoneNumber,
                phoneCodeHash: phoneCodeHash,
                phoneCode: pendingCodeIsEmail ? nil : cleanCode,
                emailVerification: emailVerification
            )
            try acceptAuthorization(authorization)
            return .ready
        } catch let error as MTProtoRPCError where error.message == "SESSION_PASSWORD_NEEDED" {
            let password = try await connection.client.account.getPassword()
            return .password(hint: password.hint ?? "")
        } catch {
            throw readableLoginError(error)
        }
    }

    func sendLoginEmailCode(to email: String) async throws -> String {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
            throw ServiceError.invalidEmailAddress
        }
        let connection = try await connection(dcID: primaryDC, media: false)
        do {
            let value = try await connection.client.account.sendVerifyEmailCode(
                purpose: loginEmailPurpose,
                email: cleanEmail
            )
            return value.emailPattern
        } catch {
            throw readableLoginError(error)
        }
    }

    func verifyLoginEmail(code: String) async throws -> RequestCodeResult {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else { throw ServiceError.emptyLoginCode }
        let connection = try await connection(dcID: primaryDC, media: false)
        do {
            let result = try await connection.client.account.verifyEmail(
                purpose: loginEmailPurpose,
                verification: .emailVerificationCode(TL.EmailVerificationCode(code: cleanCode))
            )
            guard case let .emailVerifiedLogin(value) = result else {
                throw ServiceError.invalidCodeResponse
            }
            return try handleSentCode(value.sentCode)
        } catch {
            throw readableLoginError(error)
        }
    }

    func checkPassword(_ password: String) async throws {
        let connection = try await connection(dcID: primaryDC, media: false)
        do {
            let configuration = try await connection.client.account.getPassword()
            let proof = try TelegramSRP.proof(password: password, configuration: configuration)
            let authorization = try await connection.client.auth.checkPassword(password: proof)
            try acceptAuthorization(authorization)
        } catch {
            throw readableLoginError(error)
        }
    }

    func loadChats() async throws -> [MusicChat] {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        var result: [MusicChat] = []
        var seen: Set<String> = []
        var offsetDate: Int32 = 0
        var offsetID: Int32 = 0
        var offsetPeer: TL.InputPeerType = .inputPeerEmpty(TL.InputPeerEmpty())

        while true {
            let page = try await connection.client.messages.getDialogs(
                excludePinned: false,
                folderId: nil,
                offsetDate: offsetDate,
                offsetId: offsetID,
                offsetPeer: offsetPeer,
                limit: 100,
                hash: 0
            )
            let mapped = TelegramMapping.chats(from: page)
            for chat in mapped where seen.insert(chat.id).inserted { result.append(chat) }
            guard dialogCount(page) >= 100,
                  let last = mapped.last,
                  let cursor = dialogCursor(page),
                  cursor.id != offsetID || cursor.date != offsetDate else { break }
            offsetPeer = TelegramMapping.inputPeer(for: last)
            offsetDate = cursor.date
            offsetID = cursor.id
        }
        return result
    }

    func searchMusic(
        in chat: MusicChat,
        query: String,
        offsetID: Int32 = 0,
        limit: Int32 = 30
    ) async throws -> [Track] {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        let result = try await connection.client.messages.search(
            peer: TelegramMapping.inputPeer(for: chat),
            q: query,
            filter: .inputMessagesFilterMusic(TL.InputMessagesFilterMusic()),
            minDate: 0,
            maxDate: 0,
            offsetId: offsetID,
            addOffset: 0,
            limit: limit,
            maxId: 0,
            minId: 0,
            hash: 0
        )
        return TelegramMapping.tracks(from: result)
    }

    func searchAllMusic(query: String) async throws -> [Track] {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        let result = try await connection.client.messages.searchGlobal(
            q: query,
            filter: .inputMessagesFilterMusic(TL.InputMessagesFilterMusic()),
            minDate: 0,
            maxDate: 0,
            offsetRate: 0,
            offsetPeer: .inputPeerEmpty(TL.InputPeerEmpty()),
            offsetId: 0,
            limit: 100
        )
        return TelegramMapping.tracks(from: result)
    }

    func musicCount(in chat: MusicChat) async throws -> Int {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        let result = try await connection.client.messages.search(
            peer: TelegramMapping.inputPeer(for: chat),
            q: "",
            filter: .inputMessagesFilterMusic(TL.InputMessagesFilterMusic()),
            minDate: 0,
            maxDate: 0,
            offsetId: 0,
            addOffset: 0,
            limit: 0,
            maxId: 0,
            minId: 0,
            hash: 0
        )
        return TelegramMapping.messageCount(from: result)
    }

    func comments(for track: Track, in chat: MusicChat) async throws -> [TrackComment] {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        let result = try await connection.client.messages.getReplies(
            peer: TelegramMapping.inputPeer(for: chat),
            msgId: track.messageID,
            offsetId: 0,
            offsetDate: 0,
            addOffset: 0,
            limit: 100,
            maxId: 0,
            minId: 0,
            hash: 0
        )
        return TelegramMapping.comments(from: result)
    }

    func addComment(_ rawText: String, to track: Track, in chat: MusicChat) async throws {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)

        let target: (peer: TL.InputPeerType, messageID: Int32)
        if chat.isBroadcast == true {
            let discussion = try await connection.client.messages.getDiscussionMessage(
                peer: TelegramMapping.inputPeer(for: chat),
                msgId: track.messageID
            )
            guard let resolved = TelegramMapping.discussionTarget(
                from: discussion,
                excluding: chat.id
            ) else { throw ServiceError.commentingUnavailable }
            target = (TelegramMapping.inputPeer(for: resolved.chat), resolved.messageID)
        } else {
            target = (TelegramMapping.inputPeer(for: chat), track.messageID)
        }

        let reply: TL.InputReplyToType = .inputReplyToMessage(
            TL.InputReplyToMessage(replyToMsgId: target.messageID)
        )
        _ = try await connection.client.messages.sendMessage(
            noWebpage: true,
            peer: target.peer,
            replyTo: reply,
            message: text,
            randomId: Int64.random(in: Int64.min...Int64.max)
        )
    }

    func loadPlaylistChats(from chats: [MusicChat]) async throws -> [MusicChat] {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        let filters = try await connection.client.messages.getDialogFilters()
        guard let folder = playlistFolder(in: filters.filters) else { return [] }
        let ids = Set(folderPeers(folder).compactMap(TelegramMapping.chatID(for:)))
        return chats.filter { ids.contains($0.id) }.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func createPlaylist(named rawName: String) async throws -> MusicChat {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        let updates = try await connection.client.channels.createChannel(
            broadcast: true,
            title: name,
            about: "Music playlist created by Telisten"
        )
        guard let playlist = TelegramMapping.chats(from: updates).first(where: { $0.kind == .channel }) else {
            throw ServiceError.playlistCreationFailed
        }
        try await addToPlaylistFolder(playlist, using: connection)
        return playlist
    }

    func deletePlaylist(_ playlist: MusicChat) async throws {
        guard playlist.kind == .channel, let accessHash = playlist.accessHash else {
            throw ServiceError.playlistDeletionUnavailable
        }
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        _ = try await connection.client.channels.deleteChannel(
            channel: .inputChannel(
                TL.InputChannel(channelId: playlist.peerID, accessHash: accessHash)
            )
        )
    }

    func delete(_ track: Track, from playlist: MusicChat) async throws {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        switch playlist.kind {
        case .channel:
            guard let accessHash = playlist.accessHash else {
                throw ServiceError.playlistTrackDeletionUnavailable
            }
            _ = try await connection.client.channels.deleteMessages(
                channel: .inputChannel(
                    TL.InputChannel(channelId: playlist.peerID, accessHash: accessHash)
                ),
                id: [track.messageID]
            )
        case .group, .user:
            _ = try await connection.client.messages.deleteMessages(
                revoke: true,
                id: [track.messageID]
            )
        }
    }

    func rename(_ playlist: MusicChat, to title: String) async throws {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        switch playlist.kind {
        case .channel:
            guard let accessHash = playlist.accessHash else {
                throw ServiceError.playlistRenameUnavailable
            }
            _ = try await connection.client.channels.editTitle(
                channel: .inputChannel(
                    TL.InputChannel(channelId: playlist.peerID, accessHash: accessHash)
                ),
                title: title
            )
        case .group:
            _ = try await connection.client.messages.editChatTitle(
                chatId: playlist.peerID,
                title: title
            )
        case .user:
            throw ServiceError.playlistRenameUnavailable
        }
    }

    func save(_ track: Track, from source: MusicChat, to playlist: MusicChat) async throws {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        _ = try await connection.client.messages.forwardMessages(
            dropAuthor: false,
            dropMediaCaptions: false,
            fromPeer: TelegramMapping.inputPeer(for: source),
            id: [track.messageID],
            randomId: [Int64.random(in: Int64.min...Int64.max)],
            toPeer: TelegramMapping.inputPeer(for: playlist)
        )
    }

    func upvote(_ track: Track, in chat: MusicChat) async throws {
        let connection = try await authorizedConnection(dcID: primaryDC, media: false)
        let reaction: TL.ReactionType = .reactionEmoji(TL.ReactionEmoji(emoticon: "👍"))
        _ = try await connection.client.messages.sendReaction(
            addToRecent: true,
            peer: TelegramMapping.inputPeer(for: chat),
            msgId: track.messageID,
            reaction: [reaction]
        )
    }

    func download(
        _ track: Track,
        to destination: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var dcID = track.dcID
        var offset: Int64 = 0
        let chunkSize: Int32 = 512 * 1_024

        do {
            while offset < track.size {
                try Task.checkCancellation()
                let chunk = try await fileChunk(for: track, dcID: dcID, offset: offset, limit: chunkSize)
                dcID = chunk.dcID
                guard !chunk.bytes.isEmpty else { throw ServiceError.incompleteDownload }
                try handle.write(contentsOf: chunk.bytes)
                offset += Int64(chunk.bytes.count)
                await progress(min(1, Double(offset) / Double(max(track.size, 1))))
            }
        } catch {
            throw readableDownloadError(error)
        }
    }

    func stream(
        _ track: Track,
        sourceChat: MusicChat? = nil,
        offset requestedOffset: Int64,
        length requestedLength: Int32
    ) async throws -> Data {
        let activeTrack = refreshedTracks[track.id] ?? track
        do {
            return try await streamBytes(
                activeTrack,
                offset: requestedOffset,
                length: requestedLength
            )
        } catch {
            guard isExpiredFileReference(error),
                  let sourceChat,
                  let refreshed = try await refreshReference(for: activeTrack, in: sourceChat) else {
                throw readableDownloadError(error)
            }
            refreshedTracks[track.id] = refreshed
            do {
                return try await streamBytes(
                    refreshed,
                    offset: requestedOffset,
                    length: requestedLength
                )
            } catch {
                throw readableDownloadError(error)
            }
        }
    }

    private func streamBytes(
        _ track: Track,
        offset requestedOffset: Int64,
        length requestedLength: Int32
    ) async throws -> Data {
        guard requestedOffset >= 0, requestedLength > 0, requestedOffset < track.size else {
            return Data()
        }

        let alignment: Int64 = 4_096
        let chunkSize: Int32 = 512 * 1_024
        let targetLength = Int(min(Int64(requestedLength), track.size - requestedOffset))
        var result = Data()
        result.reserveCapacity(targetLength)
        var dcID = track.dcID
        var offset = requestedOffset - (requestedOffset % alignment)
        var skip = Int(requestedOffset - offset)

        while result.count < targetLength {
            try Task.checkCancellation()
            let chunk = try await fileChunk(for: track, dcID: dcID, offset: offset, limit: chunkSize)
            dcID = chunk.dcID
            guard skip < chunk.bytes.count else { throw ServiceError.incompleteDownload }
            let count = min(targetLength - result.count, chunk.bytes.count - skip)
            result.append(chunk.bytes.subdata(in: skip..<(skip + count)))
            offset += Int64(chunk.bytes.count)
            skip = 0
            if chunk.bytes.count < Int(chunkSize), result.count < targetLength {
                throw ServiceError.incompleteDownload
            }
        }
        return result
    }

    private func refreshReference(for track: Track, in chat: MusicChat) async throws -> Track? {
        let title = track.displayTitle.replacingOccurrences(of: "_", with: " ")
        let fileTitle = track.fileName.deletingPathExtension.replacingOccurrences(of: "_", with: " ")
        var queries: [String] = []
        for value in [title, fileTitle] where !value.isEmpty && !queries.contains(value) {
            queries.append(value)
        }

        for query in queries {
            let values = try await searchMusic(in: chat, query: query, limit: 50)
            if let match = referenceMatch(for: track, in: values) { return match }
        }

        let nearby = try await searchMusic(
            in: chat,
            query: "",
            offsetID: track.messageID == Int32.max ? track.messageID : track.messageID + 1,
            limit: 8
        )
        return referenceMatch(for: track, in: nearby)
    }

    private func referenceMatch(for track: Track, in values: [Track]) -> Track? {
        values.first(where: { $0.messageID == track.messageID })
            ?? values.first(where: { $0.documentID == track.documentID })
    }

    private func isExpiredFileReference(_ error: Error) -> Bool {
        guard let rpc = error as? MTProtoRPCError else { return false }
        return rpc.message == "FILE_REFERENCE_EXPIRED" || rpc.message == "FILE_REFERENCE_INVALID"
    }

    func artwork(for track: Track) async throws -> Data? {
        guard let thumbSize = track.artworkThumbSize else { return nil }
        do {
            let chunk = try await fileChunk(
                for: track,
                dcID: track.dcID,
                offset: 0,
                limit: 512 * 1_024,
                thumbSize: thumbSize
            )
            return chunk.bytes.isEmpty ? nil : chunk.bytes
        } catch {
            throw readableDownloadError(error)
        }
    }

    func avatar(for chat: MusicChat) async throws -> Data? {
        guard let photoID = chat.avatarPhotoID, let dcID = chat.avatarDCID else { return nil }
        let location: TL.InputFileLocationType = .inputPeerPhotoFileLocation(
            TL.InputPeerPhotoFileLocation(
                big: false,
                peer: TelegramMapping.inputPeer(for: chat),
                photoId: photoID
            )
        )
        do {
            let chunk = try await fileChunk(
                at: location,
                dcID: dcID,
                offset: 0,
                limit: 256 * 1_024
            )
            return chunk.bytes.isEmpty ? nil : chunk.bytes
        } catch {
            throw readableDownloadError(error)
        }
    }

    func avatar(for account: TelegramAccount) async throws -> Data? {
        let peer = MusicChat(
            id: "account:\(account.id)",
            peerID: account.userID,
            accessHash: nil,
            kind: .user,
            title: account.displayName,
            username: account.username,
            avatarPhotoID: account.avatarPhotoID,
            avatarDCID: account.avatarDCID
        )
        return try await avatar(for: peer)
    }

    private func fileChunk(
        for track: Track,
        dcID: Int32,
        offset: Int64,
        limit: Int32,
        thumbSize: String = ""
    ) async throws -> (bytes: Data, dcID: Int32) {
        let location: TL.InputFileLocationType = .inputDocumentFileLocation(
            TL.InputDocumentFileLocation(
                id: track.documentID,
                accessHash: track.accessHash,
                fileReference: track.fileReference,
                thumbSize: thumbSize
            )
        )
        return try await fileChunk(
            at: location,
            dcID: dcID,
            offset: offset,
            limit: limit,
            priority: thumbSize.isEmpty ? .playback : .background
        )
    }

    private func fileChunk(
        at location: TL.InputFileLocationType,
        dcID: Int32,
        offset: Int64,
        limit: Int32,
        priority: FileRequestPriority = .background
    ) async throws -> (bytes: Data, dcID: Int32) {
        await fileRequestGate.enter(priority: priority)
        do {
            try Task.checkCancellation()
            let value = try await performFileRequest(
                at: location,
                dcID: dcID,
                offset: offset,
                limit: limit
            )
            await fileRequestGate.leave()
            return value
        } catch {
            await fileRequestGate.leave()
            throw error
        }
    }

    private func performFileRequest(
        at location: TL.InputFileLocationType,
        dcID: Int32,
        offset: Int64,
        limit: Int32
    ) async throws -> (bytes: Data, dcID: Int32) {
        var activeDC = dcID
        var attempt = 0
        var migrationCount = 0
        var useMediaConnection = false
        var lastError: Error?

        while attempt < 4 {
            attempt += 1
            try Task.checkCancellation()
            do {
                let connection = try await authorizedConnection(
                    dcID: activeDC,
                    media: useMediaConnection
                )
                let response = try await connection.client.upload.getFile(
                    precise: false,
                    cdnSupported: false,
                    location: location,
                    offset: offset,
                    limit: limit
                )
                switch response {
                case let .file(value):
                    if !value.bytes.isEmpty || attempt == 4 {
                        return (value.bytes, activeDC)
                    }
                    lastError = ServiceError.incompleteDownload
                case .fileCdnRedirect:
                    throw ServiceError.downloadRedirect
                }
            } catch let error as MTProtoRPCError {
                if let migrated = migratedDC(from: error.message), migrationCount < 2 {
                    activeDC = migrated
                    migrationCount += 1
                    useMediaConnection = false
                    attempt -= 1
                    lastError = error
                    continue
                }
                guard (useMediaConnection || isRetryableFileError(error)), attempt < 4 else {
                    throw error
                }
                lastError = error
            } catch {
                guard (useMediaConnection || isRetryableFileError(error)), attempt < 4 else {
                    throw error
                }
                lastError = error
            }

            await invalidateConnection(dcID: activeDC, media: useMediaConnection)
            if useMediaConnection {
                useMediaConnection = false
            } else if attempt >= 2,
                      activeDC != primaryDC,
                      hasMediaEndpoint(for: activeDC) {
                useMediaConnection = true
            }
            try await Task.sleep(for: .milliseconds(150 * attempt))
        }
        throw lastError ?? ServiceError.incompleteDownload
    }

    private func isRetryableFileError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let client = error as? MTProtoClientError {
            return switch client {
            case .timeout, .connectionClosed, .notConnected: true
            case .protocolError, .fatalBadMessage: false
            }
        }
        if let rpc = error as? MTProtoRPCError {
            return [
                "INTERNAL_SERVER_ERROR",
                "MSG_WAIT_FAILED",
                "RPC_CALL_FAIL",
                "TIMEOUT"
            ].contains(rpc.message)
        }
        if let urlError = error as? URLError {
            return [
                .cannotConnectToHost,
                .networkConnectionLost,
                .notConnectedToInternet,
                .timedOut
            ].contains(urlError.code)
        }
        return false
    }

    private func invalidateConnection(dcID: Int32, media: Bool) async {
        let key = ConnectionKey(dcID: dcID, media: media)
        authorizedConnections.remove(key)
        advanceEndpoint(dcID: dcID, media: media)
        guard let connection = connections.removeValue(forKey: key) else { return }
        try? await connection.mtproto.disconnect()
    }

    private func hasMediaEndpoint(for dcID: Int32) -> Bool {
        endpoints[dcID]?.contains(where: { $0.mediaOnly }) == true
    }

    func logOut() async {
        if let connection = connections[ConnectionKey(dcID: primaryDC, media: false)] {
            _ = try? await connection.client.auth.logOut()
        }
        await discardSession()
    }

    func discardSession() async {
        for connection in connections.values {
            try? await connection.mtproto.disconnect()
        }
        connections.removeAll()
        authorizedConnections.removeAll()
        refreshedTracks.removeAll()
        keychain.clearSessions(accountID: accountID)
        setAuthorizationSaved(false)
        phoneNumber = ""
        phoneCodeHash = ""
        pendingCodeIsEmail = false
    }

    private func connection(dcID: Int32, media: Bool) async throws -> Connection {
        let key = ConnectionKey(dcID: dcID, media: media)
        if let existing = connections[key] { return existing }
        guard let endpoint = endpoint(for: dcID, media: media) else { throw ServiceError.noConnection }
        if media, !endpoint.mediaOnly {
            return try await connection(dcID: dcID, media: false)
        }
        let sessionStorageID = endpoint.mediaOnly ? -dcID : dcID
        let sessionAccountID = accountID
        var resumeSession = keychain.loadSession(dcID: sessionStorageID, accountID: sessionAccountID)
        var lastError: Error?

        while true {
            for modulus in Self.rsaModuli {
                guard let rsaKey = RSAPublicKey(modulusHex: modulus, publicExponentHex: "010001") else { continue }
                let store = keychain
                let client = MTProtoClient(
                    host: endpoint.host,
                    port: endpoint.port,
                    configuration: MTProtoClientConfiguration(
                        rsaPublicKey: rsaKey,
                        dcID: dcID,
                        resumeSession: resumeSession,
                        requestTimeout: .seconds(45),
                        connectTimeout: .seconds(45),
                        onSessionEstablished: {
                            keys in store.saveSession(
                                keys,
                                dcID: sessionStorageID,
                                accountID: sessionAccountID
                            )
                        }
                    )
                )
                do {
                    try await client.connect()
                    let config = try await initialize(client)
                    updateEndpoints(from: config)
                    let value = Connection(mtproto: client, client: TLClient(transport: Transport(client: client)))
                    connections[key] = value
                    return value
                } catch {
                    lastError = error
                    try? await client.disconnect()
                    if resumeSession != nil { break }
                }
            }

            guard resumeSession != nil else { break }
            keychain.deleteSession(dcID: sessionStorageID, accountID: sessionAccountID)
            resumeSession = nil
        }
        throw lastError ?? ServiceError.noConnection
    }

    private func authorizedConnection(dcID: Int32, media: Bool) async throws -> Connection {
        let key = ConnectionKey(dcID: dcID, media: media)
        let target = try await connection(dcID: dcID, media: media)
        if authorizedConnections.contains(key) { return target }
        guard isAuthorizationSaved else { return target }

        let primary = try await connection(dcID: primaryDC, media: false)
        if target.mtproto === primary.mtproto {
            authorizedConnections.insert(key)
            return target
        }
        let exported = try await primary.client.auth.exportAuthorization(dcId: dcID)
        _ = try await target.client.auth.importAuthorization(id: exported.id, bytes: exported.bytes)
        authorizedConnections.insert(key)
        return target
    }

    private func initialize(_ client: MTProtoClient) async throws -> TL.Config {
        let credentials = try apiCredentials()
        let query = TL.InvokeWithLayer(
            layer: Self.layer,
            query: TL.InitConnection(
                apiId: credentials.apiID,
                deviceModel: deviceModel,
                systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                appVersion: "1.0",
                systemLangCode: Locale.current.language.languageCode?.identifier ?? "en",
                langPack: "",
                langCode: Locale.current.language.languageCode?.identifier ?? "en",
                query: TL.Help.GetConfig()
            )
        )
        return try await client.invoke(query)
    }

    private func updateEndpoints(from config: TL.Config) {
        for option in config.dcOptions where !option.ipv6 && !option.cdn {
            let endpoint = Endpoint(host: option.ipAddress, port: Int(option.port), mediaOnly: option.mediaOnly)
            if endpoints[option.id]?.contains(where: { $0.host == endpoint.host && $0.port == endpoint.port }) != true {
                endpoints[option.id, default: []].append(endpoint)
            }
        }
    }

    private func endpoint(for dcID: Int32, media: Bool) -> Endpoint? {
        let key = ConnectionKey(dcID: dcID, media: media)
        let exact = endpoints[dcID]?.filter { $0.mediaOnly == media } ?? []
        let candidates = exact.isEmpty ? (endpoints[dcID] ?? []) : exact
        guard !candidates.isEmpty else { return Self.seedEndpoints[dcID] }
        let index = endpointCursors[key, default: 0] % candidates.count
        return candidates[index]
    }

    private func advanceEndpoint(dcID: Int32, media: Bool) {
        let key = ConnectionKey(dcID: dcID, media: media)
        endpointCursors[key, default: 0] += 1
    }

    private func acceptAuthorization(_ authorization: TL.Auth.AuthorizationType) throws {
        guard case .authorization = authorization else { throw ServiceError.signUpRequired }
        guard keychain.loadSession(dcID: primaryDC, accountID: accountID) != nil else {
            throw ServiceError.sessionPersistenceFailed
        }
        let key = ConnectionKey(dcID: primaryDC, media: false)
        authorizedConnections.insert(key)
        setAuthorizationSaved(true)
        persistPrimaryDC()
    }

    private func apiCredentials() throws -> TelegramCredentials {
        guard let credentials else { throw ServiceError.notConfigured }
        return credentials
    }

    private var loginEmailPurpose: TL.EmailVerifyPurposeType {
        .emailVerifyPurposeLoginSetup(
            TL.EmailVerifyPurposeLoginSetup(
                phoneNumber: phoneNumber,
                phoneCodeHash: phoneCodeHash
            )
        )
    }

    private func sendCodeResponseWithMigration() async throws -> TL.Auth.SentCodeType {
        var currentConnection = try await connection(dcID: primaryDC, media: false)
        let credentials = try apiCredentials()
        do {
            return try await currentConnection.client.auth.sendCode(
                phoneNumber: phoneNumber,
                apiId: credentials.apiID,
                apiHash: credentials.apiHash,
                settings: TL.CodeSettings()
            )
        } catch let error as MTProtoRPCError {
            guard let dcID = migratedDC(from: error.message) else { throw error }
            primaryDC = dcID
            persistPrimaryDC()
            currentConnection = try await connection(dcID: dcID, media: false)
            return try await currentConnection.client.auth.sendCode(
                phoneNumber: phoneNumber,
                apiId: credentials.apiID,
                apiHash: credentials.apiHash,
                settings: TL.CodeSettings()
            )
        }
    }

    private func handleSentCode(_ response: TL.Auth.SentCodeType) throws -> RequestCodeResult {
        switch response {
        case let .sentCode(value):
            phoneCodeHash = value.phoneCodeHash
            switch value.type {
            case let .sentCodeTypeEmailCode(email):
                pendingCodeIsEmail = true
                return .code(hint: "Code sent to \(email.emailPattern)", isEmail: true)
            case .sentCodeTypeSetUpEmailRequired:
                pendingCodeIsEmail = true
                return .emailSetup
            default:
                pendingCodeIsEmail = false
                return .code(hint: deliveryHint(value.type), isEmail: false)
            }
        case let .sentCodeSuccess(value):
            try acceptAuthorization(value.authorization)
            return .ready
        case let .sentCodePaymentRequired(value):
            throw ServiceError.paidAuthorizationRequired(value.supportEmailAddress)
        }
    }

    private func readableLoginError(_ error: Error) -> Error {
        if error is ServiceError || error is SRPProofError || error is AppConfigurationError {
            return error
        }
        if let rpc = error as? MTProtoRPCError {
            let message: String
            switch rpc.message {
            case "API_ID_INVALID":
                message = "The Telegram API ID or hash in .env is invalid."
            case "PHONE_NUMBER_INVALID":
                message = "Telegram did not recognize that phone number. Include the full country code."
            case "PHONE_NUMBER_BANNED":
                message = "Telegram has banned this phone number."
            case "PHONE_NUMBER_FLOOD":
                message = "Telegram has temporarily limited login attempts for this phone number."
            case "PHONE_CODE_EMPTY":
                message = "Enter the login code Telegram sent you."
            case "PHONE_CODE_INVALID":
                message = "That Telegram login code is incorrect."
            case "PHONE_CODE_EXPIRED":
                message = "That login code expired. Go back and request a new one."
            case "EMAIL_INVALID":
                message = "Telegram did not accept that email address."
            case "EMAIL_NOT_ALLOWED":
                message = "Telegram does not allow that email address for login."
            case "EMAIL_VERIFY_CODE_INVALID":
                message = "That email verification code is incorrect."
            case "EMAIL_VERIFY_EXPIRED":
                message = "That email verification code expired. Request another one."
            case "PASSWORD_HASH_INVALID":
                message = "That two-step verification password is incorrect."
            case "SRP_ID_INVALID":
                message = "The password challenge expired. Request a new login code and try again."
            case "AUTH_RESTART":
                message = "Telegram restarted this login attempt. Request a new code and try again."
            case "UPDATE_APP_TO_LOGIN":
                message = "Telegram requires a newer API layer for this login."
            default:
                if rpc.message.hasPrefix("FLOOD_WAIT_"),
                   let seconds = Int(rpc.message.dropFirst("FLOOD_WAIT_".count)) {
                    message = "Too many attempts. Telegram asked you to wait \(seconds) seconds."
                } else {
                    message = "Telegram rejected the login (\(rpc.message))."
                }
            }
            return ServiceError.telegram(message)
        }
        if let client = error as? MTProtoClientError {
            switch client {
            case .timeout:
                return ServiceError.telegram("Telegram did not respond in time. Check your connection and try again.")
            case .connectionClosed, .notConnected:
                return ServiceError.telegram("The Telegram connection closed. Try again.")
            case let .protocolError(code):
                return ServiceError.telegram("Telegram rejected the saved connection key (\(code)). Try again.")
            case .fatalBadMessage:
                return ServiceError.telegram("Telegram rejected the encrypted session. Request a new code and try again.")
            }
        }
        return error
    }

    private func readableDownloadError(_ error: Error) -> Error {
        if error is ServiceError || error is CancellationError { return error }
        if let rpc = error as? MTProtoRPCError {
            switch rpc.message {
            case "FILE_REFERENCE_EXPIRED", "FILE_REFERENCE_INVALID":
                return ServiceError.expiredFileReference
            case "AUTH_KEY_UNREGISTERED":
                return ServiceError.telegram("The media session expired. Sign in again to continue playback.")
            case "LOCATION_INVALID":
                return ServiceError.telegram("Telegram no longer has this audio file at the expected location.")
            default:
                return ServiceError.telegram("Telegram could not download this track (\(rpc.message)).")
            }
        }
        if let client = error as? MTProtoClientError {
            switch client {
            case .timeout:
                return ServiceError.telegram("The audio download timed out. Check your connection and try again.")
            case .connectionClosed, .notConnected:
                return ServiceError.telegram("The Telegram media connection closed. Try the track again.")
            case let .protocolError(code):
                return ServiceError.telegram("Telegram rejected the media connection (protocol \(code)). Try the track again.")
            case .fatalBadMessage:
                return ServiceError.telegram("Telegram rejected the encrypted media session. Try the track again.")
            }
        }
        return error
    }

    private func persistPrimaryDC() {
        let defaults = UserDefaults.standard
        defaults.set(Int(primaryDC), forKey: primaryDCDefaultsKey)
        if accountID == "legacy" {
            defaults.set(Int(primaryDC), forKey: "telegram.primaryDC")
        }
    }

    private var authorizationDefaultsKey: String {
        "telegram.authorized.\(accountID)"
    }

    private var primaryDCDefaultsKey: String {
        "telegram.primaryDC.\(accountID)"
    }

    private var isAuthorizationSaved: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: authorizationDefaultsKey) != nil {
            return defaults.bool(forKey: authorizationDefaultsKey)
        }
        return accountID == "legacy" && defaults.bool(forKey: "telegram.authorized")
    }

    private func setAuthorizationSaved(_ value: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: authorizationDefaultsKey)
        if accountID == "legacy" {
            defaults.set(value, forKey: "telegram.authorized")
        }
    }

    private func migratedDC(from message: String) -> Int32? {
        let prefixes = ["PHONE_MIGRATE_", "NETWORK_MIGRATE_", "USER_MIGRATE_", "FILE_MIGRATE_"]
        guard let prefix = prefixes.first(where: message.hasPrefix) else { return nil }
        return Int32(message.dropFirst(prefix.count))
    }

    private func deliveryHint(_ type: TL.Auth.SentCodeTypeType) -> String {
        switch type {
        case .sentCodeTypeApp: "Code sent in Telegram"
        case .sentCodeTypeSms: "Code sent by SMS"
        case .sentCodeTypeCall: "Code delivered by phone call"
        case .sentCodeTypeFlashCall: "Code delivered by flash call"
        case .sentCodeTypeMissedCall: "Code delivered by missed call"
        case .sentCodeTypeEmailCode: "Code sent by email"
        case .sentCodeTypeSetUpEmailRequired: "Email verification required"
        case .sentCodeTypeFragmentSms: "Code sent through Fragment"
        case .sentCodeTypeFirebaseSms: "Code sent by SMS"
        case .sentCodeTypeSmsWord: "Enter the word sent by SMS"
        case .sentCodeTypeSmsPhrase: "Enter the phrase sent by SMS"
        }
    }

    private func dialogCursor(_ result: TL.Messages.DialogsType) -> (id: Int32, date: Int32)? {
        let dialogs: [TL.DialogType]
        let messages: [TL.MessageType]
        switch result {
        case let .dialogs(value): (dialogs, messages) = (value.dialogs, value.messages)
        case let .dialogsSlice(value): (dialogs, messages) = (value.dialogs, value.messages)
        case .dialogsNotModified: return nil
        }
        guard case let .dialog(last)? = dialogs.last else { return nil }
        for message in messages {
            if case let .message(value) = message, value.id == last.topMessage {
                return (value.id, value.date)
            }
            if case let .messageService(value) = message, value.id == last.topMessage {
                return (value.id, value.date)
            }
        }
        return nil
    }

    private func dialogCount(_ result: TL.Messages.DialogsType) -> Int {
        switch result {
        case let .dialogs(value): value.dialogs.count
        case let .dialogsSlice(value): value.dialogs.count
        case .dialogsNotModified: 0
        }
    }

    private func addToPlaylistFolder(_ playlist: MusicChat, using connection: Connection) async throws {
        let values = try await connection.client.messages.getDialogFilters().filters
        let peer = TelegramMapping.inputPeer(for: playlist)
        let filter: TL.DialogFilterType
        let filterID: Int32

        if let existing = playlistFolder(in: values) {
            filter = appending(peer, to: existing)
            filterID = folderID(existing)
        } else {
            let used = Set(values.map(folderID).filter { $0 > 0 })
            var candidate: Int32 = 2
            while used.contains(candidate) { candidate += 1 }
            filterID = candidate
            filter = .dialogFilter(
                TL.DialogFilter(
                    id: candidate,
                    title: TL.TextWithEntities(text: "_Playlist", entities: []),
                    emoticon: "🎵",
                    pinnedPeers: [],
                    includePeers: [peer],
                    excludePeers: []
                )
            )
        }
        guard try await connection.client.messages.updateDialogFilter(id: filterID, filter: filter) else {
            throw ServiceError.playlistFolderFailed
        }
    }

    private func playlistFolder(in filters: [TL.DialogFilterType]) -> TL.DialogFilterType? {
        filters.first { value in
            switch value {
            case let .dialogFilter(filter): filter.title.text == "_Playlist"
            case let .dialogFilterChatlist(filter): filter.title.text == "_Playlist"
            case .dialogFilterDefault: false
            }
        }
    }

    private func folderID(_ filter: TL.DialogFilterType) -> Int32 {
        switch filter {
        case let .dialogFilter(value): value.id
        case let .dialogFilterChatlist(value): value.id
        case .dialogFilterDefault: 0
        }
    }

    private func folderPeers(_ filter: TL.DialogFilterType) -> [TL.InputPeerType] {
        switch filter {
        case let .dialogFilter(value): value.pinnedPeers + value.includePeers
        case let .dialogFilterChatlist(value): value.pinnedPeers + value.includePeers
        case .dialogFilterDefault: []
        }
    }

    private func appending(_ peer: TL.InputPeerType, to filter: TL.DialogFilterType) -> TL.DialogFilterType {
        switch filter {
        case let .dialogFilter(value):
            var include = value.includePeers
            if !include.contains(where: { TelegramMapping.chatID(for: $0) == TelegramMapping.chatID(for: peer) }) {
                include.append(peer)
            }
            return .dialogFilter(
                TL.DialogFilter(
                    contacts: value.contacts,
                    nonContacts: value.nonContacts,
                    groups: value.groups,
                    broadcasts: value.broadcasts,
                    bots: value.bots,
                    excludeMuted: value.excludeMuted,
                    excludeRead: value.excludeRead,
                    excludeArchived: value.excludeArchived,
                    titleNoanimate: value.titleNoanimate,
                    id: value.id,
                    title: value.title,
                    emoticon: value.emoticon,
                    color: value.color,
                    pinnedPeers: value.pinnedPeers,
                    includePeers: include,
                    excludePeers: value.excludePeers
                )
            )
        case let .dialogFilterChatlist(value):
            var include = value.includePeers
            if !include.contains(where: { TelegramMapping.chatID(for: $0) == TelegramMapping.chatID(for: peer) }) {
                include.append(peer)
            }
            return .dialogFilterChatlist(
                TL.DialogFilterChatlist(
                    hasMyInvites: value.hasMyInvites,
                    titleNoanimate: value.titleNoanimate,
                    id: value.id,
                    title: value.title,
                    emoticon: value.emoticon,
                    color: value.color,
                    pinnedPeers: value.pinnedPeers,
                    includePeers: include
                )
            )
        case .dialogFilterDefault:
            return filter
        }
    }

    private var deviceModel: String {
        #if os(macOS)
        "Mac"
        #else
        "iPhone"
        #endif
    }
}
