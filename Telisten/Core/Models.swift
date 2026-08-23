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

    var initial: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).first
            .map { String($0).uppercased() } ?? "?"
    }
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

enum RepeatMode: String, CaseIterable, Codable, Sendable {
    case off
    case all
    case one

    var symbolName: String {
        self == .one ? "repeat.1" : "repeat"
    }
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
