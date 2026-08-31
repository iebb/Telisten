import Foundation

protocol LyricsProviding: Sendable {
    func lyricsCandidates(for track: Track) async throws -> [TrackLyrics]
}

enum LRCParser {
    static func lines(from value: String) -> (lines: [LyricLine], isSynced: Bool) {
        let rawLines = value.components(separatedBy: .newlines)
        let offset = rawLines.compactMap(metadataOffset).last ?? 0
        var timed: [(time: TimeInterval, order: Int, text: String)] = []

        for (order, raw) in rawLines.enumerated() {
            var remainder = raw[...]
            var timestamps: [TimeInterval] = []
            while remainder.first == "[", let close = remainder.firstIndex(of: "]") {
                let token = remainder[remainder.index(after: remainder.startIndex)..<close]
                guard let timestamp = timestamp(String(token)) else { break }
                timestamps.append(max(0, timestamp + offset))
                remainder = remainder[remainder.index(after: close)...]
            }

            let text = stripEnhancedTimestamps(String(remainder))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !timestamps.isEmpty, !text.isEmpty else { continue }
            timed.append(contentsOf: timestamps.map { ($0, order, text) })
        }

        if !timed.isEmpty {
            let sorted = timed.sorted {
                if $0.time != $1.time { return $0.time < $1.time }
                return $0.order < $1.order
            }
            return (
                sorted.enumerated().map {
                    LyricLine(sequence: $0.offset, time: $0.element.time, text: $0.element.text)
                },
                true
            )
        }

        let plain = rawLines.compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isMetadataLine(trimmed) else { return nil }
            let text = stripEnhancedTimestamps(trimmed)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return (
            plain.enumerated().map { LyricLine(sequence: $0.offset, time: nil, text: $0.element) },
            false
        )
    }

    private static func timestamp(_ token: String) -> TimeInterval? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2,
           let minutes = Double(parts[0]),
           let seconds = Double(parts[1]),
           (0..<60).contains(seconds) {
            return minutes * 60 + seconds
        }
        if parts.count == 3,
           let hours = Double(parts[0]),
           let minutes = Double(parts[1]),
           let seconds = Double(parts[2]),
           (0..<60).contains(minutes), (0..<60).contains(seconds) {
            return hours * 3_600 + minutes * 60 + seconds
        }
        return nil
    }

    private static func metadataOffset(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("[offset:"), value.hasSuffix("]") else { return nil }
        let start = value.index(value.startIndex, offsetBy: 8)
        guard let milliseconds = Double(value[start..<value.index(before: value.endIndex)]) else { return nil }
        return milliseconds / 1_000
    }

    private static func isMetadataLine(_ value: String) -> Bool {
        guard value.hasPrefix("["), let close = value.firstIndex(of: "]") else { return false }
        let token = value[value.index(after: value.startIndex)..<close].lowercased()
        return ["ar:", "al:", "ti:", "au:", "by:", "re:", "ve:", "length:", "offset:"].contains {
            token.hasPrefix($0)
        }
    }

    private static func stripEnhancedTimestamps(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"<\d{1,3}:\d{1,2}(?:\.\d{1,3})?>"#,
            with: "",
            options: .regularExpression
        )
    }
}

enum LyricsServerConfiguration {
    static let defaultAddress = "https://lrclib.net"
    static let defaultURL = URL(string: defaultAddress)!

    static func normalizedURL(from address: String) -> URL? {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "https://\(value)" }

        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              components.host?.isEmpty == false else { return nil }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
    }

    static func endpoint(_ name: String, at serverURL: URL) -> URL {
        let apiURL = serverURL.lastPathComponent.lowercased() == "api"
            ? serverURL
            : serverURL.appending(path: "api", directoryHint: .isDirectory)
        return apiURL.appending(path: name)
    }
}

struct LRCLIBProvider: LyricsProviding {
    private struct Response: Decodable, Sendable {
        var id: Int64?
        var trackName: String
        var artistName: String
        var albumName: String?
        var duration: Double
        var instrumental: Bool
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    private let serverURL: URL

    init(serverURL: URL = LyricsServerConfiguration.defaultURL) {
        self.serverURL = serverURL
    }

    func lyricsCandidates(for track: Track) async throws -> [TrackLyrics] {
        let title = cleaned(track.displayTitle)
        let artist = cleaned(track.artist)
        var responses: [Response] = []
        var lastError: Error?

        if !artist.isEmpty {
            do {
                if let exact = try await exactMatch(title: title, artist: artist, duration: track.duration) {
                    responses.append(exact)
                }
            } catch {
                lastError = error
            }

            do {
                responses.append(contentsOf: try await search(title: title, artist: artist))
            } catch {
                lastError = error
            }
        }

        do {
            // Telegram audio tags often contain an uploader or circle name instead of
            // LRCLIB's canonical artist. Title and duration are enough to recover that match.
            responses.append(contentsOf: try await search(title: title, artist: ""))
        } catch {
            lastError = error
        }

        var ranked = rank(responses, for: track, title: title, artist: artist)
        if ranked.isEmpty {
            do {
                responses.append(contentsOf: try await keywordSearch(title))
                ranked = rank(responses, for: track, title: title, artist: artist)
            } catch {
                lastError = error
            }
        }

        let fileTitle = cleaned(track.fileName.deletingPathExtension)
        if ranked.isEmpty, !fileTitle.isEmpty, comparable(fileTitle) != comparable(title) {
            do {
                responses.append(contentsOf: try await search(title: fileTitle, artist: ""))
                responses.append(contentsOf: try await keywordSearch(fileTitle))
                ranked = rank(responses, for: track, title: fileTitle, artist: artist)
            } catch {
                lastError = error
            }
        }

        if ranked.isEmpty, responses.isEmpty, let lastError { throw lastError }

        var seen: Set<String> = []
        return ranked.compactMap { candidate in
            guard seen.insert(candidate.lyrics.matchKey).inserted else { return nil }
            return candidate.lyrics
        }
        .prefix(8)
        .map { $0 }
    }

    private func rank(
        _ values: [Response],
        for track: Track,
        title: String,
        artist: String
    ) -> [(lyrics: TrackLyrics, score: Int, difference: Double)] {
        var seenResponses: Set<String> = []
        return values.compactMap { response -> (lyrics: TrackLyrics, score: Int, difference: Double)? in
            guard seenResponses.insert(responseKey(response)).inserted,
                  isPlausible(response, title: title, artist: artist, duration: track.duration),
                  !response.instrumental,
                  let lyrics = makeLyrics(from: response, trackID: track.id) else { return nil }
            let score = matchScore(response, title: title, artist: artist, duration: track.duration)
            guard score >= 35 else { return nil }
            let difference = track.duration > 0 ? abs(response.duration - track.duration) : 0
            return (lyrics, score, difference)
        }
        .sorted { lhs, rhs in
            if lhs.lyrics.isSynced != rhs.lyrics.isSynced {
                return lhs.lyrics.isSynced
            }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.difference < rhs.difference
        }
    }

    private func exactMatch(title: String, artist: String, duration: TimeInterval) async throws -> Response? {
        var components = URLComponents(
            url: LyricsServerConfiguration.endpoint("get", at: serverURL),
            resolvingAgainstBaseURL: false
        )
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
        var components = URLComponents(
            url: LyricsServerConfiguration.endpoint("search", at: serverURL),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }
        return try await request(url, as: [Response].self, permitsNotFound: false) ?? []
    }

    private func keywordSearch(_ title: String) async throws -> [Response] {
        var components = URLComponents(
            url: LyricsServerConfiguration.endpoint("search", at: serverURL),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "q", value: title)]
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
            let parsed = LRCParser.lines(from: synced)
            if !parsed.lines.isEmpty {
                return TrackLyrics(
                    trackID: trackID,
                    source: "LRCLIB",
                    lines: parsed.lines,
                    isSynced: parsed.isSynced,
                    matchID: value.id,
                    matchedTitle: value.trackName,
                    matchedArtist: value.artistName,
                    matchedAlbum: value.albumName,
                    matchedDuration: value.duration
                )
            }
        }
        guard let plain = value.plainLyrics, !plain.isEmpty else { return nil }
        let lines = plain.components(separatedBy: .newlines).enumerated().map {
            LyricLine(sequence: $0.offset, time: nil, text: $0.element)
        }
        return TrackLyrics(
            trackID: trackID,
            source: "LRCLIB",
            lines: lines,
            isSynced: false,
            matchID: value.id,
            matchedTitle: value.trackName,
            matchedArtist: value.artistName,
            matchedAlbum: value.albumName,
            matchedDuration: value.duration
        )
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
        if candidate.syncedLyrics?.isEmpty == false { score += 18 }
        return score
    }

    private func isPlausible(
        _ candidate: Response,
        title: String,
        artist: String,
        duration: TimeInterval
    ) -> Bool {
        let expectedTitle = comparable(title)
        let candidateTitle = comparable(candidate.trackName)
        guard !expectedTitle.isEmpty,
              candidateTitle == expectedTitle
                || candidateTitle.contains(expectedTitle)
                || expectedTitle.contains(candidateTitle) else { return false }

        let expectedArtist = comparable(artist)
        let candidateArtist = comparable(candidate.artistName)
        let artistMatches = expectedArtist.isEmpty
            || candidateArtist == expectedArtist
            || candidateArtist.contains(expectedArtist)
            || expectedArtist.contains(candidateArtist)
        guard !expectedArtist.isEmpty, !artistMatches, duration > 0 else { return true }

        // A mismatched artist is common in Telegram tags, but a close duration makes an
        // exact/normalized title safe enough. Reject distant same-title covers by default.
        return abs(candidate.duration - duration) <= 8
    }

    private func responseKey(_ value: Response) -> String {
        if let id = value.id { return "id:\(id)" }
        return [
            comparable(value.trackName),
            comparable(value.artistName),
            String(Int(value.duration.rounded()))
        ].joined(separator: "|")
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

}

actor LyricsService {
    private var provider: any LyricsProviding
    private let cacheURL: URL
    private let selectionsURL: URL
    private var cached: [String: TrackLyrics] = [:]
    private var fetchedMatches: [String: [TrackLyrics]] = [:]
    private var selectedMatchKeys: [String: String] = [:]

    init(provider: any LyricsProviding = LRCLIBProvider()) {
        self.provider = provider
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let root = caches.appending(path: "Telisten", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cacheURL = root.appending(path: "lyrics-index.json")
        selectionsURL = root.appending(path: "lyrics-selections.json")
        if let data = try? Data(contentsOf: cacheURL),
           let values = try? JSONDecoder().decode([TrackLyrics].self, from: data) {
            cached = Dictionary(uniqueKeysWithValues: values.map { ($0.trackID, $0) })
        }
        if let data = try? Data(contentsOf: selectionsURL),
           let values = try? JSONDecoder().decode([String: String].self, from: data) {
            selectedMatchKeys = values
        }
    }

    func lyrics(for track: Track, attachedLRC: [AttachedLRC] = []) async throws -> LyricsResult? {
        let attachedMatches = attachedLRC.compactMap { attachedLyrics($0, for: track) }
        if let fetched = fetchedMatches[track.id], !fetched.isEmpty {
            let matches = merged(attachedMatches, with: fetched)
            fetchedMatches[track.id] = matches
            return result(for: track.id, matches: matches)
        }

        let fallback = cached[track.id]
        var matches = attachedMatches
        do {
            matches = merged(matches, with: try await provider.lyricsCandidates(for: track))
        } catch {
            guard !matches.isEmpty || fallback != nil else { throw error }
        }

        if let fallback,
           !matches.contains(where: { $0.matchKey == fallback.matchKey }),
           selectedMatchKeys[track.id] == fallback.matchKey {
            matches.append(fallback)
        }
        guard !matches.isEmpty else {
            return fallback.map { LyricsResult(selected: $0, matches: [$0]) }
        }

        fetchedMatches[track.id] = matches
        guard let result = result(for: track.id, matches: matches) else { return nil }
        cached[track.id] = result.selected
        persist()
        return result
    }

    func select(_ value: TrackLyrics) {
        cached[value.trackID] = value
        selectedMatchKeys[value.trackID] = value.matchKey
        persist()
        persistSelections()
    }

    private func attachedLyrics(_ value: AttachedLRC, for track: Track) -> TrackLyrics? {
        let parsed = LRCParser.lines(from: value.contents)
        guard !parsed.lines.isEmpty else { return nil }
        return TrackLyrics(
            trackID: track.id,
            source: "Telegram · \(value.fileName)",
            lines: parsed.lines,
            isSynced: parsed.isSynced,
            matchedTitle: value.fileName.deletingPathExtension,
            matchedArtist: nil,
            matchedAlbum: nil,
            matchedDuration: nil
        )
    }

    private func merged(_ preferred: [TrackLyrics], with fallback: [TrackLyrics]) -> [TrackLyrics] {
        var seen: Set<String> = []
        return (preferred + fallback)
            .filter { seen.insert($0.matchKey).inserted }
            .sorted { lhs, rhs in
                if lhs.isSynced != rhs.isSynced { return lhs.isSynced }
                let lhsAttached = lhs.source.hasPrefix("Telegram ·")
                let rhsAttached = rhs.source.hasPrefix("Telegram ·")
                if lhsAttached != rhsAttached { return lhsAttached }
                return false
            }
    }

    func setServerURL(_ serverURL: URL) {
        provider = LRCLIBProvider(serverURL: serverURL)
        fetchedMatches.removeAll()
    }

    private func result(for trackID: String, matches: [TrackLyrics]) -> LyricsResult? {
        guard let defaultMatch = matches.first else { return nil }
        let selected = selectedMatchKeys[trackID].flatMap { key in
            matches.first(where: { $0.matchKey == key })
        } ?? defaultMatch
        return LyricsResult(selected: selected, matches: matches)
    }

    private func persist() {
        let values = cached.values.sorted { $0.trackID < $1.trackID }
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func persistSelections() {
        guard let data = try? JSONEncoder().encode(selectedMatchKeys) else { return }
        try? data.write(to: selectionsURL, options: .atomic)
    }
}
