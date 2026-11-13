#if DEBUG
@preconcurrency import AVFoundation
import Foundation

/// A short, original sample synthesized in code for demo mode (`--demo`).
///
/// Demo tracks have no Telegram file behind them, so demo playback uses this
/// locally generated audio instead of the network: a soft four-chord progression
/// (Cmaj7 – Am7 – Fmaj7 – G, twice) with a sine arpeggio, a warm pad and a bass
/// note, ending in a gentle fade. It is written once as 16-bit mono PCM WAV to
/// the caches directory and then repeated back to back up to each demo track's
/// stated duration (see `loopedAsset(from:duration:)`), so the scrubber, the
/// elapsed/remaining labels and timed lyrics all describe what actually plays.
enum DemoAudioSample {
    static let sampleRate = 44_100
    static let duration: TimeInterval = 32
    /// Bump when the synthesis changes so a stale cached file is not reused.
    static let fileName = "telisten-demo-sample-v1.wav"

    enum SampleError: Error {
        case missingAudioTrack
    }

    /// Writes the sample to `directory` unless a complete copy already exists.
    static func fileURL(in directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) throws -> URL {
        let url = directory.appendingPathComponent(fileName)
        let expectedSize = 44 + Int(duration * Double(sampleRate)) * 2
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == expectedSize {
            return url
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try wavData().write(to: url, options: .atomic)
        return url
    }

    /// A complete RIFF/WAVE file: 16-bit little-endian mono PCM.
    static func wavData(duration: TimeInterval = duration, sampleRate: Int = sampleRate) -> Data {
        let frameCount = max(0, Int(duration * Double(sampleRate)))
        let dataSize = frameCount * 2
        var data = Data(capacity: 44 + dataSize)
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF")
        append32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1) // PCM
        append16(1) // mono
        append32(sampleRate)
        append32(sampleRate * 2) // byte rate
        append16(2) // block align
        append16(16) // bits per sample
        append("data")
        append32(dataSize)

        let samples = synthesize(frameCount: frameCount, sampleRate: sampleRate)
        samples.withUnsafeBufferPointer { buffer in
            for value in buffer {
                let clamped = max(-1, min(1, value))
                append16(Int(UInt16(bitPattern: Int16((clamped * 32_767).rounded()))))
            }
        }
        return data
    }

    /// Repeats the sample at `url` back to back until exactly `duration` seconds,
    /// so an `AVPlayerItem` reports the demo track's stated length.
    @MainActor
    static func loopedAsset(from url: URL, duration: TimeInterval) async throws -> AVAsset {
        let source = AVURLAsset(url: url)
        guard let sourceTrack = try await source.loadTracks(withMediaType: .audio).first else {
            throw SampleError.missingAudioTrack
        }
        let sourceDuration = try await source.load(.duration)
        let composition = AVMutableComposition()
        guard sourceDuration.seconds > 0,
              let audio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw SampleError.missingAudioTrack
        }
        let timescale = CMTimeScale(sampleRate)
        let target = CMTime(seconds: max(duration, 1), preferredTimescale: timescale)
        var cursor = CMTime.zero
        while cursor < target {
            let length = CMTimeMinimum(sourceDuration, target - cursor)
            try audio.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: sourceTrack, at: cursor)
            cursor = cursor + length
        }
        return composition
    }

    // MARK: - Synthesis

    private struct Chord {
        let bass: Int
        let notes: [Int]
    }

    /// MIDI note numbers; eight bars of four seconds each.
    private static let progression: [Chord] = [
        Chord(bass: 48, notes: [60, 64, 67, 71]), // Cmaj7
        Chord(bass: 45, notes: [57, 60, 64, 67]), // Am7
        Chord(bass: 41, notes: [57, 60, 65, 69]), // Fmaj7
        Chord(bass: 43, notes: [55, 59, 62, 67]), // G
        Chord(bass: 48, notes: [60, 64, 67, 71]), // Cmaj7
        Chord(bass: 45, notes: [57, 60, 64, 67]), // Am7
        Chord(bass: 41, notes: [57, 60, 65, 69]), // Fmaj7
        Chord(bass: 43, notes: [55, 62, 65, 67])  // G7sus-ish turnaround
    ]
    private static let arpeggioPattern = [0, 1, 2, 3, 2, 1, 2, 3]

    private static func frequency(_ midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    static func synthesize(frameCount: Int, sampleRate: Int) -> [Float] {
        guard frameCount > 0, sampleRate > 0 else { return [] }
        var output = [Float](repeating: 0, count: frameCount)
        let rate = Double(sampleRate)
        let barLength = duration / Double(progression.count)
        let stepLength = barLength / Double(arpeggioPattern.count)
        let twoPi = 2 * Double.pi

        func addTone(start: Double, length: Double, frequency: Double, gain: Double, attack: Double, decay: Double) {
            let first = max(0, Int(start * rate))
            let last = min(frameCount, Int((start + length) * rate))
            guard first < last else { return }
            for index in first..<last {
                let local = Double(index) / rate - start
                let attackGain = min(1, local / attack)
                let releaseGain = min(1, (length - local) / 0.08)
                let envelope = attackGain * releaseGain * exp(-local * decay)
                let phase = twoPi * frequency * local
                // A touch of second harmonic gives the sine a soft, bell-like tone.
                let tone = sin(phase) + 0.18 * sin(2 * phase)
                output[index] += Float(gain * envelope * tone)
            }
        }

        var time = 0.0
        while time < Double(frameCount) / rate {
            for (barIndex, chord) in progression.enumerated() {
                let barStart = time + Double(barIndex) * barLength
                addTone(start: barStart, length: barLength, frequency: frequency(chord.bass),
                        gain: 0.16, attack: 0.04, decay: 0.45)
                for note in chord.notes.prefix(3) {
                    addTone(start: barStart, length: barLength, frequency: frequency(note),
                            gain: 0.035, attack: 0.9, decay: 0.12)
                }
                for (step, noteIndex) in arpeggioPattern.enumerated() {
                    addTone(start: barStart + Double(step) * stepLength,
                            length: min(1.6, barLength), frequency: frequency(chord.notes[noteIndex] + 12),
                            gain: 0.11, attack: 0.012, decay: 2.6)
                }
            }
            time += duration
        }

        let fadeIn = 0.4 * rate
        let fadeOut = 2.5 * rate
        for index in 0..<frameCount {
            let position = Double(index)
            let remaining = Double(frameCount - index)
            let fade = min(1, position / fadeIn, remaining / fadeOut)
            output[index] = Float(Double(output[index]) * fade)
        }
        return output
    }
}
#endif
