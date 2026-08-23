import Foundation

actor CacheStore {
    struct Entry: Codable, Sendable {
        var trackID: String
        var fileName: String
        var byteCount: Int64
        var lastAccess: Date
    }

    private let root: URL
    private let indexURL: URL
    private var entries: [String: Entry] = [:]
    private var limit: Int64

    init(limit: Int64 = 2 * 1_024 * 1_024 * 1_024) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = caches.appending(path: "Telisten", directoryHint: .isDirectory)
        indexURL = root.appending(path: "cache-index.json")
        self.limit = limit
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let values = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Dictionary(uniqueKeysWithValues: values.map { ($0.trackID, $0) })
        }
    }

    func localURL(for track: Track) -> URL? {
        guard var entry = entries[track.id] else { return nil }
        let url = root.appending(path: entry.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            entries.removeValue(forKey: track.id)
            persist()
            return nil
        }
        entry.lastAccess = .now
        entries[track.id] = entry
        persist()
        return url
    }

    func temporaryURL(for track: Track) -> URL {
        root.appending(path: ".\(track.documentID).download")
    }

    func commit(_ temporaryURL: URL, track: Track) throws -> URL {
        let ext = (track.fileName as NSString).pathExtension
        let name = ext.isEmpty ? track.id.replacingOccurrences(of: ":", with: "-") : "\(track.id.replacingOccurrences(of: ":", with: "-")).\(ext)"
        let destination = root.appending(path: name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        entries[track.id] = Entry(trackID: track.id, fileName: name, byteCount: track.size, lastAccess: .now)
        evictIfNeeded(excluding: track.id)
        persist()
        return destination
    }

    func remove(_ track: Track) throws {
        guard let entry = entries.removeValue(forKey: track.id) else { return }
        let url = root.appending(path: entry.fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        persist()
    }

    func removeAll() throws {
        for entry in entries.values {
            let url = root.appending(path: entry.fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        entries.removeAll()
        persist()
    }

    func cachedTrackIDs() -> Set<String> {
        Set(entries.keys)
    }

    func totalBytes() -> Int64 {
        entries.values.reduce(0) { $0 + $1.byteCount }
    }

    func setLimit(_ bytes: Int64) {
        limit = bytes
        evictIfNeeded(excluding: nil)
        persist()
    }

    private func evictIfNeeded(excluding protectedID: String?) {
        var total = entries.values.reduce(0) { $0 + $1.byteCount }
        for entry in entries.values.sorted(by: { $0.lastAccess < $1.lastAccess }) where total > limit {
            guard entry.trackID != protectedID else { continue }
            try? FileManager.default.removeItem(at: root.appending(path: entry.fileName))
            entries.removeValue(forKey: entry.trackID)
            total -= entry.byteCount
        }
    }

    private func persist() {
        let values = entries.values.sorted { $0.trackID < $1.trackID }
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
