import Foundation

// Run with Scripts/test-offline-lyrics.sh. Uses production models and service,
// an isolated on-disk library and a provider that fails every offline request.
private actor Provider: LyricsProviding {
    private(set) var calls = 0
    let values: [TrackLyrics]
    let offline: Bool

    init(_ values: [TrackLyrics] = [], offline: Bool = false) {
        self.values = values
        self.offline = offline
    }

    func lyricsCandidates(for track: Track) async throws -> [TrackLyrics] {
        calls += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return values
    }
}

@main
enum OfflineLyricsTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "telisten-lyrics-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let track = Track(
            documentID: 123, accessHash: 0, fileReference: Data(), dcID: 2,
            messageID: 1, chatID: "playlist", title: "Test Song", artist: "Artist",
            fileName: "Test Song.mp3", mimeType: "audio/mpeg", duration: 180,
            size: 100, date: .now
        )
        let timed = TrackLyrics(
            trackID: track.id, source: "LRCLIB",
            lines: [LyricLine(sequence: 0, time: 1, text: "First line")],
            isSynced: true, matchID: 1
        )
        let plain = TrackLyrics(
            trackID: track.id, source: "LRCLIB",
            lines: [LyricLine(sequence: 0, time: nil, text: "Alternate line")],
            isSynced: false, matchID: 2
        )
        let online = Provider([timed, plain])
        let firstLaunch = LyricsService(provider: online, directory: directory)
        let first = try await firstLaunch.lyrics(for: track)
        precondition(first?.selected == timed)
        _ = try await firstLaunch.lyrics(for: track)
        let calls = await online.calls
        precondition(calls == 1, "Replaying a matched song must not query the provider")
        await firstLaunch.select(plain)

        let offline = Provider(offline: true)
        let secondLaunch = LyricsService(provider: offline, directory: directory)
        let local = await secondLaunch.cachedLyrics(for: track)
        precondition(local?.selected == plain, "Explicit selection must survive restart")
        precondition(local?.matches.count == 2, "Alternate matches must be available offline")
        let replay = try await secondLaunch.lyrics(for: track)
        precondition(replay?.selected == plain)
        let offlineCalls = await offline.calls
        precondition(offlineCalls == 0, "A saved match must never contact the provider")

        // Forwarding to a new playlist keeps the document identity and its lyrics.
        var forwarded = track
        forwarded.chatID = "other-account-playlist"
        forwarded.messageID = 987
        let shared = try await secondLaunch.lyrics(for: forwarded)
        precondition(shared?.selected == plain)

        await secondLaunch.setServerURL(URL(string: "https://unreachable.invalid")!)
        let afterServerChange = try await secondLaunch.lyrics(for: track)
        precondition(afterServerChange?.selected == plain)
        precondition(afterServerChange?.matches.count == 2)

        let legacyDirectory = directory.appending(path: "legacy")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode([timed]).write(to: legacyDirectory.appending(path: "lyrics-index.json"))
        let legacy = LyricsService(provider: offline, directory: legacyDirectory)
        let restored = try await legacy.lyrics(for: track)
        precondition(restored?.selected == timed, "Existing single-match caches must work immediately")

        // Attached LRC remains available after restart even when the server was offline.
        let lrcDirectory = directory.appending(path: "attachments")
        let attachments = LyricsService(provider: offline, directory: lrcDirectory)
        let lrc = AttachedLRC(id: "lrc-1", fileName: "Test Song.lrc", contents: "[00:01.00]Attached lyric")
        let attached = try await attachments.lyrics(for: track, attachedLRC: [lrc])
        precondition(attached?.selected.isSynced == true)
        let restoredAttachments = LyricsService(provider: offline, directory: lrcDirectory)
        let restoredLRC = try await restoredAttachments.lyrics(for: track)
        precondition(restoredLRC?.selected == attached?.selected)
        print("PASS: cached replay, persisted selection/candidates, shared document, server change, existing cache, attached LRC")
    }
}
