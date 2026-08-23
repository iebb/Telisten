import Foundation

actor ArtworkStore {
    private let root: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = caches.appending(path: "Telisten/Artwork", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func data(for track: Track) -> Data? {
        try? Data(contentsOf: url(for: track))
    }

    func save(_ data: Data, for track: Track) {
        try? data.write(to: url(for: track), options: .atomic)
    }

    private func url(for track: Track) -> URL {
        root.appending(path: track.id.replacingOccurrences(of: ":", with: "-") + ".image")
    }
}
