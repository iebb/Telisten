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

private actor DelayedProvider: LyricsProviding {
    private var response: CheckedContinuation<[TrackLyrics], Never>?
    private var started: CheckedContinuation<Void, Never>?
    func lyricsCandidates(for track: Track) async throws -> [TrackLyrics] {
        await withCheckedContinuation { response = $0; started?.resume(); started = nil }
    }
    func waitUntilStarted() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(with lyrics: TrackLyrics) { response?.resume(returning: [lyrics]); response = nil }
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
        // Real audio tags, not just injected strings: MP3 TXXX/USLT, M4A ©lyr,
        // and FLAC Vorbis comments containing synchronized LRC.
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/EmbeddedLyrics")
        for ext in ["mp3", "m4a", "flac"] {
            let text = await EmbeddedLyricsReader.read(from: fixtures.appending(path: "timed.\(ext)"))
            precondition(text != nil, "Embedded \(ext) lyrics must be readable")
            let parsed = LRCParser.lines(from: text!)
            precondition(parsed.isSynced && parsed.lines.count == 2)
            precondition(parsed.lines[0].text == "Embedded first line")
        }
        // FFmpeg emits lyrics in a TXXX tag; also exercise a standard ID3 USLT frame.
        let usltURL = directory.appending(path: "standard-uslt.mp3")
        let mp3 = try Data(contentsOf: fixtures.appending(path: "timed.mp3"))
        let oldTagSize = mp3[6..<10].reduce(0) { ($0 << 7) | Int($1) }
        func syncSafe(_ size: Int) -> Data {
            Data([UInt8((size >> 21) & 127), UInt8((size >> 14) & 127), UInt8((size >> 7) & 127), UInt8(size & 127)])
        }
        let words = "[00:00.00]Standard ID3 lyric\n[00:00.05]Next ID3 line"
        let payload = Data([3]) + Data("eng".utf8) + Data([0]) + Data(words.utf8)
        let frame = Data("USLT".utf8) + syncSafe(payload.count) + Data([0, 0]) + payload
        let tag = Data("ID3".utf8) + Data([4, 0, 0]) + syncSafe(frame.count) + frame
        try (tag + mp3.dropFirst(10 + oldTagSize)).write(to: usltURL)
        let standardLyrics = await EmbeddedLyricsReader.read(from: usltURL)
        precondition(standardLyrics == words, "Standard MP3 USLT lyrics must be readable")
        let embeddedDirectory = directory.appending(path: "embedded")
        let embeddedProvider = Provider([timed])
        let embeddedService = LyricsService(provider: embeddedProvider, directory: embeddedDirectory)
        _ = try await embeddedService.lyrics(for: track)
        let embedded = await embeddedService.embeddedLyrics(
            for: track, fileURL: fixtures.appending(path: "timed.mp3")
        )
        precondition(embedded?.selected.source == "Embedded lyrics", "Embedded lyrics replace an automatic server match")
        precondition(embedded?.matches.count == 2, "Other matches remain selectable")
        let embeddedRestart = LyricsService(provider: embeddedProvider, directory: embeddedDirectory)
        let restoredEmbedded = try await embeddedRestart.lyrics(for: track)
        precondition(restoredEmbedded?.selected == embedded?.selected)
        let embeddedCalls = await embeddedProvider.calls
        precondition(embeddedCalls == 1, "Embedded replay must not query online")
        await embeddedService.select(timed)
        let manual = await embeddedService.storeEmbeddedLyrics("[00:01]Local", for: track)
        precondition(manual?.selected == timed, "Respect an explicit alternative selection")

        let plainService = LyricsService(provider: offline, directory: directory.appending(path: "plain-embedded"))
        let plainEmbedded = await plainService.storeEmbeddedLyrics("First plain line\nSecond plain line", for: track)
        precondition(plainEmbedded?.selected.isSynced == false)
        precondition(plainEmbedded?.selected.lines.count == 2)
        let blank = await plainService.storeEmbeddedLyrics(" \n[ar:Artist]\n", for: track)
        precondition(blank == nil, "Empty/metadata-only tags must not suppress other lyrics")
        let unreadable = await EmbeddedLyricsReader.read(from: directory.appending(path: "missing.mp3"))
        precondition(unreadable == nil, "Unreadable files must fall back safely")
        let delayed = DelayedProvider()
        let streaming = LyricsService(provider: delayed, directory: directory.appending(path: "streaming"))
        let onlineTask = Task { try await streaming.lyrics(for: track) }
        await delayed.waitUntilStarted()
        _ = await streaming.storeEmbeddedLyrics("[00:00]Downloaded while searching", for: track)
        await delayed.finish(with: timed)
        let streamingResult = try await onlineTask.value
        precondition(streamingResult?.selected.source == "Embedded lyrics", "Late server responses must not overwrite embedded lyrics")
        print("PASS: cached replay, persisted selection/candidates, shared document, server change, existing cache, attached LRC")
        print("PASS: MP3/M4A/FLAC embedded tags, timestamps, priority, persisted embedded lyrics, plain text, explicit selection, unreadable files")
    }
}
