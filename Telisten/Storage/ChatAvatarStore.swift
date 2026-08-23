import Foundation

actor ChatAvatarStore {
    private let root: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = caches.appending(path: "Telisten/ChatAvatars", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func data(for chat: MusicChat) -> Data? {
        try? Data(contentsOf: url(for: chat))
    }

    func save(_ data: Data, for chat: MusicChat) {
        try? data.write(to: url(for: chat), options: .atomic)
    }

    private func url(for chat: MusicChat) -> URL {
        let chatID = chat.id.replacingOccurrences(of: ":", with: "-")
        return root.appending(path: "\(chatID)-\(chat.avatarPhotoID ?? 0).image")
    }
}
