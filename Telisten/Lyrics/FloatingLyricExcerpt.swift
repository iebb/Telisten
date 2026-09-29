import Foundation

/// Selects whole lyric lines; plain text is paged manually, never assigned fake timestamps.
struct FloatingLyricExcerpt: Equatable {
    let current: LyricLine?
    let next: LyricLine?
    let plainLineCount: Int

    init(lyrics: TrackLyrics, time: TimeInterval, plainLineIndex: Int = 0) {
        let nonempty = lyrics.lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if lyrics.isSynced {
            let timed = nonempty.filter { $0.time?.isFinite == true }.sorted {
                if $0.time == $1.time { return $0.sequence < $1.sequence }
                return ($0.time ?? 0) < ($1.time ?? 0)
            }
            let playbackTime = time.isFinite ? max(0, time) : 0
            let index = timed.lastIndex { ($0.time ?? .infinity) <= playbackTime }
            current = index.map { timed[$0] }
            let nextIndex = index.map { $0 + 1 } ?? 0
            next = timed.indices.contains(nextIndex) ? timed[nextIndex] : nil
            plainLineCount = 0
        } else {
            let index = min(max(0, plainLineIndex), max(0, nonempty.count - 1))
            current = nonempty.indices.contains(index) ? nonempty[index] : nil
            next = nonempty.indices.contains(index + 1) ? nonempty[index + 1] : nil
            plainLineCount = nonempty.count
        }
    }
}
