import Foundation

@main
enum FloatingLyricsTests {
    static func main() {
        let timed = TrackLyrics(trackID: "one", source: "Fixture", lines: [
            LyricLine(sequence: 3, time: 20, text: "Third"),
            LyricLine(sequence: 0, time: 5, text: "First"),
            LyricLine(sequence: 1, time: 8, text: "  "),
            LyricLine(sequence: 2, time: 10, text: "Second"),
            LyricLine(sequence: 4, time: .infinity, text: "Invalid")
        ], isSynced: true)

        let intro = FloatingLyricExcerpt(lyrics: timed, time: 0)
        precondition(intro.current == nil && intro.next?.text == "First", "Don't sing a line before its timestamp")
        let first = FloatingLyricExcerpt(lyrics: timed, time: 5)
        precondition(first.current?.text == "First" && first.next?.text == "Second")
        let middle = FloatingLyricExcerpt(lyrics: timed, time: 19.9)
        precondition(middle.current?.text == "Second" && middle.next?.text == "Third")
        let end = FloatingLyricExcerpt(lyrics: timed, time: 200)
        precondition(end.current?.text == "Third" && end.next == nil)
        let seekBack = FloatingLyricExcerpt(lyrics: timed, time: 6)
        precondition(seekBack.current?.text == "First", "Backward seeking must recompute the active line")
        precondition(FloatingLyricExcerpt(lyrics: timed, time: .nan).current == nil)

        let plain = TrackLyrics(trackID: "two", source: "Fixture", lines: [
            LyricLine(sequence: 0, time: nil, text: "One"),
            LyricLine(sequence: 1, time: nil, text: "\n"),
            LyricLine(sequence: 2, time: nil, text: "Two"),
            LyricLine(sequence: 3, time: nil, text: "Three")
        ], isSynced: false)
        let unsynced = FloatingLyricExcerpt(lyrics: plain, time: 1_000)
        precondition(unsynced.current?.text == "One" && unsynced.next?.text == "Two")
        precondition(unsynced.plainLineCount == 3, "Plain lyrics must not infer timing from audio progress")
        precondition(FloatingLyricExcerpt(lyrics: plain, time: 0, plainLineIndex: 1).current?.text == "Two")
        precondition(FloatingLyricExcerpt(lyrics: plain, time: 0, plainLineIndex: -1).current?.text == "One")
        let overflow = FloatingLyricExcerpt(lyrics: plain, time: 0, plainLineIndex: 100)
        precondition(overflow.current?.text == "Three" && overflow.next == nil)
        let empty = TrackLyrics(trackID: "empty", source: "Fixture", lines: [], isSynced: false)
        precondition(FloatingLyricExcerpt(lyrics: empty, time: 0).current == nil)
        print("PASS: timed boundaries, intro, last line, blank/invalid lines, backward seek, manual plain lyrics, empty lyrics")
    }
}
