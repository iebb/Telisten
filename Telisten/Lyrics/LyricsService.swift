import Foundation

protocol LyricsProviding: Sendable {
    func lyrics(for track: Track) async throws -> TrackLyrics?
}

struct LRCLIBProvider: LyricsProviding {
    private struct Response: Decodable {
        var trackName: String
        var artistName: String
        var duration: Double
        var instrumental: Bool
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    func lyrics(for track: Track) async throws -> TrackLyrics? {
        let title = cleaned(track.displayTitle)
        let artist = cleaned(track.artist)

        if !artist.isEmpty,
           let exact = try await exactMatch(title: title, artist: artist, duration: track.duration),
           let lyrics = makeLyrics(from: exact, trackID: track.id) {
            return lyrics
        }

        let candidates = try await search(title: title, artist: artist)
        guard let best = candidates
            .filter({ !$0.instrumental && ($0.plainLyrics?.isEmpty == false || $0.syncedLyrics?.isEmpty == false) })
            .map({ ($0, matchScore($0, title: title, artist: artist, duration: track.duration)) })
            .filter({ $0.1 >= 35 })
            .max(by: { $0.1 < $1.1 })?.0 else { return nil }
        return makeLyrics(from: best, trackID: track.id)
    }

    private func exactMatch(title: String, artist: String, duration: TimeInterval) async throws -> Response? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if (1...3_600).contains(duration) {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { return nil }
        return try await request(url, as: Response.self, permitsNotFound: true)
    }

    private func search(title: String, artist: String) async throws -> [Response] {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        if artist.isEmpty {
            components?.queryItems = [URLQueryItem(name: "q", value: title)]
        } else {
            components?.queryItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artist)
            ]
        }
        guard let url = components?.url else { return [] }
        return try await request(url, as: [Response].self, permitsNotFound: false) ?? []
    }

    private func request<Value: Decodable>(
        _ url: URL,
        as type: Value.Type,
        permitsNotFound: Bool
    ) async throws -> Value? {
        var request = URLRequest(url: url)
        request.setValue("Telisten/1.0 (SwiftUI Telegram music player)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if permitsNotFound, http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func makeLyrics(from value: Response, trackID: String) -> TrackLyrics? {
        if value.instrumental { return nil }
        if let synced = value.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty {
                return TrackLyrics(trackID: trackID, source: "LRCLIB", lines: lines, isSynced: true)
            }
        }
        guard let plain = value.plainLyrics, !plain.isEmpty else { return nil }
        let lines = plain.components(separatedBy: .newlines).enumerated().map {
            LyricLine(sequence: $0.offset, time: nil, text: $0.element)
        }
        return TrackLyrics(trackID: trackID, source: "LRCLIB", lines: lines, isSynced: false)
    }

    private func matchScore(
        _ candidate: Response,
        title: String,
        artist: String,
        duration: TimeInterval
    ) -> Int {
        let expectedTitle = comparable(title)
        let candidateTitle = comparable(candidate.trackName)
        let expectedArtist = comparable(artist)
        let candidateArtist = comparable(candidate.artistName)
        var score = 0

        if candidateTitle == expectedTitle { score += 55 }
        else if candidateTitle.contains(expectedTitle) || expectedTitle.contains(candidateTitle) { score += 25 }
        if !expectedArtist.isEmpty {
            if candidateArtist == expectedArtist { score += 30 }
            else if candidateArtist.contains(expectedArtist) || expectedArtist.contains(candidateArtist) { score += 14 }
        }
        if duration > 0 {
            let difference = abs(candidate.duration - duration)
            if difference <= 2 { score += 20 }
            else if difference <= 8 { score += 10 }
        }
        if candidate.syncedLyrics?.isEmpty == false { score += 5 }
        return score
    }

    private func cleaned(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "_", with: " ")
        let suffix = #"\s*[\(\[].*?(official|audio|video|lyrics?|remaster(?:ed)?|version).*?[\)\]]\s*$"#
        result = result.replacingOccurrences(of: suffix, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func comparable(_ value: String) -> String {
        cleaned(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func parseLRC(_ value: String) -> [LyricLine] {
        value.components(separatedBy: .newlines).compactMap { raw -> (TimeInterval, String)? in
            guard raw.first == "[", let close = raw.firstIndex(of: "]") else { return nil }
            let timestamp = raw[raw.index(after: raw.startIndex)..<close]
            let parts = timestamp.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { return nil }
            let text = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return (minutes * 60 + seconds, text)
        }
        .enumerated()
        .map { LyricLine(sequence: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}

actor LyricsService {
    private let provider: any LyricsProviding
    private let cacheURL: URL
    private var cached: [String: TrackLyrics] = [:]

    init(provider: any LyricsProviding = LRCLIBProvider()) {
        self.provider = provider
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let root = caches.appending(path: "Telisten", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cacheURL = root.appending(path: "lyrics-index.json")
        if let data = try? Data(contentsOf: cacheURL),
           let values = try? JSONDecoder().decode([TrackLyrics].self, from: data) {
            cached = Dictionary(uniqueKeysWithValues: values.map { ($0.trackID, $0) })
        }
    }

    func lyrics(for track: Track) async throws -> TrackLyrics? {
        if let value = cached[track.id] { return value }
        guard let value = try await provider.lyrics(for: track) else { return nil }
        cached[track.id] = value
        persist()
        return value
    }

    private func persist() {
        let values = cached.values.sorted { $0.trackID < $1.trackID }
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
