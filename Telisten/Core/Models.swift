import Foundation

struct TelegramCredentials: Codable, Equatable, Sendable {
    var apiID: Int32
    var apiHash: String
}

struct TelegramAccount: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var userID: Int64
    var displayName: String
    var username: String?
    var avatarPhotoID: Int64? = nil
    var avatarDCID: Int32? = nil

    var initial: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).first
            .map { String($0).uppercased() } ?? "?"
    }
}

struct SearchBotConfig: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var botName: String
    var searchPrefix: String
    var searchSuffix: String

    init(
        id: UUID = UUID(),
        botName: String,
        searchPrefix: String = "",
        searchSuffix: String = ""
    ) {
        self.id = id
        self.botName = botName
        self.searchPrefix = searchPrefix
        self.searchSuffix = searchSuffix
    }

    var normalizedBotName: String {
        let value = botName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("@") ? String(value.dropFirst()) : value
    }

    var displayBotName: String {
        "@\(normalizedBotName)"
    }

    func command(for query: String) -> String {
        searchPrefix + query.trimmingCharacters(in: .whitespacesAndNewlines) + searchSuffix
    }

    var commandPreview: String {
        "Send \(searchPrefix)<query>\(searchSuffix) to bot"
    }
}

enum BotSearchButtonAction: Hashable, Sendable {
    case sendText(String)
    case callback(messageID: Int32, data: Data)
    case openURL(URL)
    case unsupported
}

struct BotSearchButton: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var action: BotSearchButtonAction
}

struct BotSearchMessage: Identifiable, Hashable, Sendable {
    var id: Int32
    var isOutgoing: Bool
    var text: String
    var date: Date
    var buttonRows: [[BotSearchButton]]
    var track: Track?
}

struct TelegramLyricsAttachment: Identifiable, Hashable, Sendable {
    var id: String { "\(dcID):\(documentID)" }
    var documentID: Int64
    var accessHash: Int64
    var fileReference: Data
    var dcID: Int32
    var messageID: Int32
    var chatID: String
    var fileName: String
    var mimeType: String
    var size: Int64
    var date: Date
}

struct AttachedLRC: Hashable, Sendable {
    var id: String
    var fileName: String
    var contents: String
}

enum PeerKind: String, Codable, Sendable {
    case user
    case group
    case channel
}

struct MusicChat: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var peerID: Int64
    var accessHash: Int64?
    var kind: PeerKind
    var title: String
    var username: String?
    var avatarPhotoID: Int64? = nil
    var avatarDCID: Int32? = nil
    var isBroadcast: Bool? = nil
    var isPinned: Bool? = nil
    var isAdmin: Bool? = nil
    var canInviteUsers: Bool? = nil
    var canManageCalls: Bool? = nil

    var symbolName: String {
        switch kind {
        case .user: "person.fill"
        case .group: "person.2.fill"
        case .channel: "megaphone.fill"
        }
    }
}

struct Track: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(dcID):\(documentID)" }
    var documentID: Int64
    var accessHash: Int64
    var fileReference: Data
    var dcID: Int32
    var messageID: Int32
    var chatID: String
    var title: String
    var artist: String
    var fileName: String
    var mimeType: String
    var duration: TimeInterval
    var size: Int64
    var date: Date
    var upvoteCount: Int32?
    var didUpvote: Bool?
    var artworkThumbSize: String? = nil
    var artworkPreview: Data? = nil

    var displayTitle: String {
        title.isEmpty ? fileName.deletingPathExtension : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Unknown artist" : artist
    }
}

struct LyricLine: Identifiable, Codable, Hashable, Sendable {
    var id: Int { sequence }
    var sequence: Int
    var time: TimeInterval?
    var text: String
}

struct TrackLyrics: Codable, Hashable, Sendable {
    var trackID: String
    var source: String
    var lines: [LyricLine]
    var isSynced: Bool
    var matchID: Int64? = nil
    var matchedTitle: String? = nil
    var matchedArtist: String? = nil
    var matchedAlbum: String? = nil
    var matchedDuration: TimeInterval? = nil

    var matchKey: String {
        if let matchID { return "\(source):\(matchID)" }
        return [
            source,
            matchedTitle ?? "",
            matchedArtist ?? "",
            matchedDuration.map { String($0) } ?? ""
        ].joined(separator: "|")
    }
}

struct LyricsResult: Sendable {
    var selected: TrackLyrics
    var matches: [TrackLyrics]
}

enum LyricsLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(TrackLyrics)
    case unavailable
    case failed(String)
}

struct TrackComment: Identifiable, Equatable, Sendable {
    var id: String
    var author: String
    var text: String
    var date: Date
}

enum CommentsLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded([TrackComment])
    case failed(String)
}

struct VoteState: Equatable, Sendable {
    var count: Int32
    var chosen: Bool
    var isSending = false
}

enum PlaybackMode: String, CaseIterable, Codable, Sendable {
    case shuffle
    case order
    case reverseOrder
    case repeatOne

    var symbolName: String {
        switch self {
        case .shuffle: "shuffle"
        case .order: "list.number"
        case .reverseOrder: "arrow.up.arrow.down"
        case .repeatOne: "repeat.1"
        }
    }

    var title: String {
        switch self {
        case .shuffle: "Shuffle"
        case .order: "Order"
        case .reverseOrder: "Reverse order"
        case .repeatOne: "Repeat one"
        }
    }

    var next: Self {
        let values = Self.allCases
        let index = values.firstIndex(of: self) ?? 0
        return values[(index + 1) % values.count]
    }
}

struct GroupCallReference: Equatable, Sendable {
    var id: Int64
    var accessHash: Int64
    var title: String
    var participantCount: Int32
}

struct GroupCallPublishEndpoint: Sendable {
    var url: String
    var key: String
    var call: GroupCallReference
}

struct ListenTogetherPresence: Equatable, Sendable {
    var title: String
    var artist: String
    var elapsed: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool

    var telegramTitle: String {
        let prefix = isPlaying ? "♫ " : "Ⅱ "
        let timing = "\(Self.duration(elapsed))/\(Self.duration(duration))"
        let suffix = " · \(timing)"
        let identity = artist.isEmpty ? title : "\(title) — \(artist)"
        let availableIdentityCharacters = max(1, 64 - prefix.count - suffix.count)
        return prefix + String(identity.prefix(availableIdentityCharacters)) + suffix
    }

    init(track: Track, elapsed: TimeInterval, isPlaying: Bool) {
        title = track.displayTitle
        artist = track.displayArtist
        self.elapsed = max(0, elapsed)
        duration = max(0, track.duration)
        self.isPlaying = isPlaying
    }

    init?(telegramTitle: String) {
        let isPlaying: Bool
        let body: Substring
        if telegramTitle.hasPrefix("♫ ") {
            isPlaying = true
            body = telegramTitle.dropFirst(2)
        } else if telegramTitle.hasPrefix("Ⅱ ") {
            isPlaying = false
            body = telegramTitle.dropFirst(2)
        } else {
            return nil
        }

        guard let timingSeparator = body.lastIndex(of: "·") else { return nil }
        let identity = body[..<timingSeparator].trimmingCharacters(in: .whitespaces)
        let timing = body[body.index(after: timingSeparator)...]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "/", maxSplits: 1)
        guard timing.count == 2,
              let elapsed = Self.seconds(String(timing[0])),
              let duration = Self.seconds(String(timing[1])) else { return nil }

        let pieces = identity.components(separatedBy: " — ")
        guard let title = pieces.first, !title.isEmpty else { return nil }
        self.title = title
        artist = pieces.dropFirst().joined(separator: " — ")
        self.elapsed = elapsed
        self.duration = duration
        self.isPlaying = isPlaying
    }

    private static func seconds(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct ListenTogetherSession: Equatable, Sendable {
    enum Role: String, Sendable {
        case host
        case listener
    }

    var chat: MusicChat
    var call: GroupCallReference
    var role: Role
    var presence: ListenTogetherPresence?
}

enum ListenTogetherState: Equatable, Sendable {
    case idle
    case preparing
    case live(ListenTogetherSession)
    case failed(String)
}

enum ConnectionPhase: Equatable, Sendable {
    case signedOut
    case connecting
    case code(phone: String, hint: String, isEmail: Bool)
    case emailAddress
    case emailVerification(email: String, hint: String)
    case password(hint: String)
    case ready
}

enum QRCodeLoginState: Equatable, Sendable {
    case idle
    case loading
    case waiting(url: URL, expiresAt: Date, status: String? = nil)
    case failed(String)
}

struct DownloadStatus: Equatable, Sendable {
    var progress: Double
    var isCached: Bool

    static let none = DownloadStatus(progress: 0, isCached: false)
}

extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
