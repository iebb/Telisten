import Foundation

enum CacheLimits {
    static let minimum: Int64 = 100_000_000
    static let maximum: Int64 = 50_000_000_000
    static let defaultValue: Int64 = 2_000_000_000
    static let options: [Int64] = [
        100_000_000,
        250_000_000,
        500_000_000,
        1_000_000_000,
        2_000_000_000,
        5_000_000_000,
        10_000_000_000,
        20_000_000_000,
        50_000_000_000
    ]
}

struct PartialCacheLocation: Sendable {
    var dataURL: URL
    var stateURL: URL
}

private struct PartialDownloadState: Codable {
    var trackID: String
    var fileName: String
    var fileSize: Int64
    var completedOffsets: [Int64]
    var lastAccess: Date
}

actor ProgressiveAudioTransfer {
    private static let chunkSize: Int64 = 512 * 1_024

    private let fileSize: Int64
    private let trackID: String
    private let provider: AudioByteProvider
    private var fileURL: URL
    private let stateURL: URL
    private var handle: FileHandle?
    private var completedOffsets: Set<Int64> = []
    private var requests: [Int64: Task<Data, Error>] = [:]

    init(
        trackID: String,
        fileSize: Int64,
        location: PartialCacheLocation,
        provider: @escaping AudioByteProvider
    ) {
        self.trackID = trackID
        self.fileSize = fileSize
        fileURL = location.dataURL
        stateURL = location.stateURL
        self.provider = provider

        if let data = try? Data(contentsOf: location.stateURL),
           let state = try? JSONDecoder().decode(PartialDownloadState.self, from: data),
           state.trackID == trackID,
           state.fileSize == fileSize,
           state.fileName == location.dataURL.lastPathComponent,
           FileManager.default.fileExists(atPath: location.dataURL.path) {
            completedOffsets = Set(state.completedOffsets.filter {
                $0 >= 0 && $0 < fileSize && $0 % Self.chunkSize == 0
            })
        } else {
            try? FileManager.default.removeItem(at: location.dataURL)
            try? FileManager.default.removeItem(at: location.stateURL)
        }
    }

    func bytes(at requestedOffset: Int64, length requestedLength: Int32) async throws -> Data {
        guard requestedOffset >= 0, requestedLength > 0, requestedOffset < fileSize else {
            return Data()
        }

        let end = min(fileSize, requestedOffset + Int64(requestedLength))
        var offset = requestedOffset
        var result = Data()
        result.reserveCapacity(Int(end - requestedOffset))

        while offset < end {
            try Task.checkCancellation()
            let chunkOffset = offset - (offset % Self.chunkSize)
            let chunk = try await chunk(at: chunkOffset)
            let start = Int(offset - chunkOffset)
            guard start < chunk.count else { throw TransferError.incompleteData }
            let count = min(Int(end - offset), chunk.count - start)
            result.append(chunk.subdata(in: start..<(start + count)))
            offset += Int64(count)
        }
        return result
    }

    func downloadAll(progress: @escaping @Sendable (Double) async -> Void) async throws {
        var offset: Int64 = 0
        while offset < fileSize {
            try Task.checkCancellation()
            let data = try await chunk(at: offset)
            guard !data.isEmpty else { throw TransferError.incompleteData }
            offset += Int64(data.count)
            await progress(min(1, Double(offset) / Double(max(fileSize, 1))))
        }
        try handle?.synchronize()
    }

    func didCommit(to destination: URL) {
        fileURL = destination
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func chunk(at offset: Int64) async throws -> Data {
        if completedOffsets.contains(offset) {
            return try readChunk(at: offset)
        }
        if let request = requests[offset] {
            let data = try await request.value
            return try storeFetched(data, at: offset)
        }

        let provider = provider
        let length = Int32(min(Self.chunkSize, fileSize - offset))
        let request = Task<Data, Error> {
            try await provider(offset, length)
        }
        requests[offset] = request

        do {
            let data = try await request.value
            requests.removeValue(forKey: offset)
            return try storeFetched(data, at: offset)
        } catch {
            requests.removeValue(forKey: offset)
            throw error
        }
    }

    private func storeFetched(_ data: Data, at offset: Int64) throws -> Data {
        if completedOffsets.contains(offset) {
            return try readChunk(at: offset)
        }
        let expectedLength = Int(min(Self.chunkSize, fileSize - offset))
        guard data.count == expectedLength else { throw TransferError.incompleteData }
        try write(data, at: offset)
        completedOffsets.insert(offset)
        persistState()
        return data
    }

    private func prepareFile() throws -> FileHandle {
        if let handle { return handle }
        if !FileManager.default.fileExists(atPath: fileURL.path),
           !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
            throw TransferError.cannotCreateFile
        }
        let value = try FileHandle(forUpdating: fileURL)
        handle = value
        return value
    }

    private func write(_ data: Data, at offset: Int64) throws {
        let handle = try prepareFile()
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)
    }

    private func readChunk(at offset: Int64) throws -> Data {
        let handle = try prepareFile()
        try handle.seek(toOffset: UInt64(offset))
        let length = Int(min(Self.chunkSize, fileSize - offset))
        guard let data = try handle.read(upToCount: length), data.count == length else {
            throw TransferError.incompleteData
        }
        return data
    }

    private func persistState() {
        let state = PartialDownloadState(
            trackID: trackID,
            fileName: fileURL.lastPathComponent,
            fileSize: fileSize,
            completedOffsets: completedOffsets.sorted(),
            lastAccess: .now
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private enum TransferError: LocalizedError {
        case cannotCreateFile
        case incompleteData

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile: "The offline cache could not create a download file."
            case .incompleteData: "Telegram stopped sending this track before the download completed."
            }
        }
    }
}

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

    init(limit: Int64 = CacheLimits.defaultValue) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = caches.appending(path: "Telisten", directoryHint: .isDirectory)
        indexURL = root.appending(path: "cache-index.json")
        self.limit = min(max(limit, CacheLimits.minimum), CacheLimits.maximum)
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

    func partialLocation(for track: Track) -> PartialCacheLocation {
        let base = ".\(safeName(for: track.id))"
        return PartialCacheLocation(
            dataURL: root.appending(path: "\(base).download"),
            stateURL: root.appending(path: "\(base).partial.json")
        )
    }

    func commit(_ temporaryURL: URL, track: Track) throws -> URL {
        let ext = (track.fileName as NSString).pathExtension
        let name = ext.isEmpty ? track.id.replacingOccurrences(of: ":", with: "-") : "\(track.id.replacingOccurrences(of: ":", with: "-")).\(ext)"
        let destination = root.appending(path: name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        try? FileManager.default.removeItem(at: partialLocation(for: track).stateURL)
        let size = fileSize(at: destination) ?? track.size
        entries[track.id] = Entry(trackID: track.id, fileName: name, byteCount: size, lastAccess: .now)
        evictIfNeeded(preserving: [track.id])
        persist()
        return destination
    }

    func remove(_ track: Track) throws {
        if let entry = entries.removeValue(forKey: track.id) {
            let url = root.appending(path: entry.fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        let partial = partialLocation(for: track)
        try? FileManager.default.removeItem(at: partial.dataURL)
        try? FileManager.default.removeItem(at: partial.stateURL)
        persist()
    }

    func removeAll() throws {
        for entry in entries.values {
            let url = root.appending(path: entry.fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        for partial in partialRecords() {
            try? FileManager.default.removeItem(at: partial.dataURL)
            try? FileManager.default.removeItem(at: partial.stateURL)
        }
        entries.removeAll()
        persist()
    }

    func cachedTrackIDs() -> Set<String> {
        reconcileIndex()
        return Set(entries.keys)
    }

    func totalBytes() -> Int64 {
        reconcileIndex()
        return entries.values.reduce(0) { $0 + $1.byteCount }
            + partialRecords().reduce(0) { $0 + $1.byteCount }
    }

    func setLimit(_ bytes: Int64, preserving trackIDs: Set<String> = []) {
        limit = min(max(bytes, CacheLimits.minimum), CacheLimits.maximum)
        evictIfNeeded(preserving: trackIDs)
        persist()
    }

    private func evictIfNeeded(preserving protectedIDs: Set<String>) {
        let partials = partialRecords().sorted { $0.lastAccess < $1.lastAccess }
        var total = entries.values.reduce(0) { $0 + $1.byteCount }
            + partials.reduce(0) { $0 + $1.byteCount }
        for partial in partials where total > limit {
            guard !protectedIDs.contains(partial.trackID) else { continue }
            try? FileManager.default.removeItem(at: partial.dataURL)
            try? FileManager.default.removeItem(at: partial.stateURL)
            total -= partial.byteCount
        }
        for entry in entries.values.sorted(by: { $0.lastAccess < $1.lastAccess }) where total > limit {
            guard !protectedIDs.contains(entry.trackID) else { continue }
            try? FileManager.default.removeItem(at: root.appending(path: entry.fileName))
            entries.removeValue(forKey: entry.trackID)
            total -= entry.byteCount
        }
    }

    private func reconcileIndex() {
        var changed = false
        for (trackID, entry) in Array(entries) {
            let url = root.appending(path: entry.fileName)
            guard let size = fileSize(at: url) else {
                entries.removeValue(forKey: trackID)
                changed = true
                continue
            }
            if size != entry.byteCount {
                entries[trackID]?.byteCount = size
                changed = true
            }
        }
        if changed { persist() }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return Int64(size)
    }

    private func allocatedSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
            return nil
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    private func partialRecords() -> [PartialRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls.compactMap { stateURL in
            guard stateURL.lastPathComponent.hasSuffix(".partial.json"),
                  let data = try? Data(contentsOf: stateURL),
                  let state = try? JSONDecoder().decode(PartialDownloadState.self, from: data) else {
                return nil
            }
            let dataURL = root.appending(path: state.fileName)
            guard let byteCount = allocatedSize(at: dataURL) else {
                try? FileManager.default.removeItem(at: stateURL)
                return nil
            }
            return PartialRecord(
                trackID: state.trackID,
                dataURL: dataURL,
                stateURL: stateURL,
                byteCount: byteCount,
                lastAccess: state.lastAccess
            )
        }
    }

    private func safeName(for value: String) -> String {
        value.replacingOccurrences(of: ":", with: "-")
    }

    private struct PartialRecord {
        var trackID: String
        var dataURL: URL
        var stateURL: URL
        var byteCount: Int64
        var lastAccess: Date
    }

    private func persist() {
        let values = entries.values.sorted { $0.trackID < $1.trackID }
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
