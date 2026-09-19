import Foundation

typealias AudioByteProvider = @Sendable (_ offset: Int64, _ length: Int32) async throws -> Data

@main
enum CacheStoreTests {
    static func track(_ id: Int64, size: Int64 = 1024) -> Track {
        Track(documentID: id, accessHash: 1, fileReference: Data(), dcID: 2,
              messageID: 1, chatID: "c:1", title: "Offline \(id)", artist: "Test",
              fileName: "offline.mp3", mimeType: "audio/mpeg", duration: 10,
              size: size, date: .now)
    }

    static func main() async throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appending(path: "telisten-cache-tests-\(UUID())")
        try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sandbox) }
        let root = sandbox.appending(path: "Application Support/Telisten/Audio")
        let legacy = sandbox.appending(path: "Caches/Telisten")
        try fm.createDirectory(at: legacy.appending(path: "Artwork"), withIntermediateDirectories: true)
        try Data([1]).write(to: legacy.appending(path: "Artwork/keep.image"))

        let song = track(1)
        let audio = Data(repeating: 0x42, count: Int(song.size))
        let oldFile = legacy.appending(path: "2-1.mp3")
        try audio.write(to: oldFile)
        let entry = CacheStore.Entry(trackID: song.id, fileName: "2-1.mp3", byteCount: song.size, lastAccess: .now)
        // Duplicate old records must not crash launch.
        try JSONEncoder().encode([entry, entry]).write(to: legacy.appending(path: "cache-index.json"))
        try audio.write(to: legacy.appending(path: "2-2.mp3"))
        let cache = CacheStore(rootURL: root, legacyURL: legacy)
        precondition(cache.initialCachedTrackIDs == [song.id, track(2).id])
        let url = await cache.localURL(for: song)
        let migratedBytes = try Data(contentsOf: url!)
        precondition(migratedBytes == audio)
        precondition(fm.fileExists(atPath: legacy.appending(path: "Artwork/keep.image").path))
        precondition(!fm.fileExists(atPath: oldFile.path))
        let rootValues = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        precondition(rootValues.isExcludedFromBackup == true)

        let downloaded = track(3)
        let temporary = await cache.partialLocation(for: downloaded).dataURL
        try audio.write(to: temporary)
        _ = try await cache.commit(temporary, track: downloaded)
        let relaunched = CacheStore(rootURL: root)
        precondition(relaunched.initialDownloadedTracks[downloaded.id] == downloaded)
        let downloadedURL = await relaunched.localURL(for: downloaded)
        let downloadedBytes = try Data(contentsOf: downloadedURL!)
        precondition(downloadedBytes == audio)
        _ = try await relaunched.commit(temporary, track: downloaded)
        precondition(fm.fileExists(atPath: downloadedURL!.path), "A duplicate commit must not delete the original")

        // An unreadable central index and missing library metadata must not hide
        // committed audio; per-file records restore the whole track offline.
        try Data("broken index".utf8).write(to: root.appending(path: "cache-index.json"))
        try fm.removeItem(at: legacy)
        let recovered = CacheStore(rootURL: root)
        precondition(recovered.initialDownloadedTracks[downloaded.id] == downloaded)
        precondition(recovered.initialCachedTrackIDs.contains(downloaded.id))

        // Persist partial bytes across launch without fetching them a second time.
        let partialTrack = track(4, size: 1024 * 1024)
        let location = await recovered.partialLocation(for: partialTrack)
        let transfer = ProgressiveAudioTransfer(trackID: partialTrack.id, fileSize: partialTrack.size, location: location) { _, count in
            Data(repeating: 0x55, count: Int(count))
        }
        let firstChunk = try await transfer.bytes(at: 0, length: 512 * 1024)
        let resumed = ProgressiveAudioTransfer(trackID: partialTrack.id, fileSize: partialTrack.size, location: location) { _, _ in
            fatalError("Cached partial bytes must not be requested from Telegram again")
        }
        let resumedChunk = try await resumed.bytes(at: 0, length: 512 * 1024)
        precondition(resumedChunk == firstChunk)
        precondition(!CacheStore(rootURL: root).initialCachedTrackIDs.contains(partialTrack.id))

        let migratedPartialRoot = sandbox.appending(path: "migrated-partials")
        let partialMigration = CacheStore(rootURL: migratedPartialRoot, legacyURL: root)
        let migratedLocation = await partialMigration.partialLocation(for: partialTrack)
        let migratedTransfer = ProgressiveAudioTransfer(trackID: partialTrack.id, fileSize: partialTrack.size, location: migratedLocation) { _, _ in
            fatalError("Migrated partial bytes must be reused offline")
        }
        let migratedChunk = try await migratedTransfer.bytes(at: 0, length: 512 * 1024)
        precondition(migratedChunk == firstChunk)
        // Return the completed files moved by the migration for the remaining tests.
        _ = CacheStore(rootURL: root, legacyURL: migratedPartialRoot)

        // Explicit deletion must remove recovery records as well.
        try await recovered.remove(downloaded)
        precondition(!CacheStore(rootURL: root).initialCachedTrackIDs.contains(downloaded.id))

        // Do not advertise truncated downloads as completed.
        let shortFile = await recovered.partialLocation(for: downloaded).dataURL
        try Data([1]).write(to: shortFile)
        do {
            _ = try await recovered.commit(shortFile, track: downloaded)
            fatalError("An incomplete file was committed")
        } catch is CocoaError { }

        // iOS container paths can change on app updates. Persist only filenames.
        let relocated = sandbox.appending(path: "new-container/Audio")
        try fm.createDirectory(at: relocated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: root, to: relocated)
        let afterUpdate = CacheStore(rootURL: relocated)
        let movedURL = await afterUpdate.localURL(for: song)
        let movedBytes = try Data(contentsOf: movedURL!)
        precondition(movedBytes == audio)

        let boundedRoot = sandbox.appending(path: "bounded")
        let bounded = CacheStore(limit: CacheLimits.minimum, rootURL: boundedRoot)
        for id: Int64 in [10, 11] {
            let large = track(id, size: 60_000_000)
            let staging = await bounded.partialLocation(for: large).dataURL
            fm.createFile(atPath: staging.path, contents: nil)
            let handle = try FileHandle(forWritingTo: staging)
            try handle.truncate(atOffset: UInt64(large.size))
            try handle.close()
            _ = try await bounded.commit(staging, track: large)
        }
        precondition(CacheStore(rootURL: boundedRoot).initialCachedTrackIDs == [track(11).id],
                     "Eviction must remove recovery records so evicted downloads do not reappear")
        print("PASS: durable downloads, migration, orphan recovery, relaunch, lost index, metadata recovery, partial resume, deletion, truncated files, container relocation")
    }
}
