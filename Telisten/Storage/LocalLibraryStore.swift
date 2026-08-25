import Foundation

struct LocalPlaylistMirror: Codable, Equatable, Sendable {
    var playlists: [MusicChat] = []
    var tracksByPlaylist: [String: [Track]] = [:]
    var trackOrders: [String: [String]] = [:]
}

final class LocalLibraryStore {
    private struct Snapshot: Codable {
        var version = 1
        var downloadedTracks: [String: Track] = [:]
        var playlistsByAccount: [String: LocalPlaylistMirror] = [:]
    }

    private let fileURL: URL
    private var snapshot: Snapshot

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = applicationSupport.appending(path: "Telisten", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "local-library.json")

        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = stored
        } else {
            snapshot = Snapshot()
        }
    }

    var downloadedTracks: [String: Track] {
        snapshot.downloadedTracks
    }

    func playlistMirror(for accountID: String) -> LocalPlaylistMirror {
        snapshot.playlistsByAccount[accountID] ?? LocalPlaylistMirror()
    }

    func saveDownloadedTracks(_ tracks: [String: Track]) {
        guard snapshot.downloadedTracks != tracks else { return }
        snapshot.downloadedTracks = tracks
        persist()
    }

    func savePlaylistMirror(_ mirror: LocalPlaylistMirror, for accountID: String) {
        guard snapshot.playlistsByAccount[accountID] != mirror else { return }
        snapshot.playlistsByAccount[accountID] = mirror
        persist()
    }

    func removePlaylistMirror(for accountID: String) {
        guard snapshot.playlistsByAccount.removeValue(forKey: accountID) != nil else { return }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
