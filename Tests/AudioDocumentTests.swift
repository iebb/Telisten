import AVFoundation
import Foundation

@main
enum AudioDocumentTests {
    static func main() async throws {
        precondition(AudioDocumentFormat.isWAV(fileName: "Song.WAV", mimeType: "application/octet-stream"))
        for mime in ["audio/wav", "audio/wave", "audio/x-wav", "audio/vnd.wave", " Audio/X-WAV; codecs=1"] {
            precondition(AudioDocumentFormat.isWAV(fileName: "upload", mimeType: mime))
        }
        for name in ["notes.txt", "song.wav.pdf", "waveform.png", "wav"] {
            precondition(!AudioDocumentFormat.isWAV(fileName: name, mimeType: "application/octet-stream"))
        }
        precondition(!AudioDocumentFormat.isWAV(fileName: "song.mp3", mimeType: "audio/mpeg"))

        // Exercise the player's AVFoundation backend with an actual PCM WAV,
        // including duration discovery when Telegram supplies no duration.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("telisten-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for frame in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100)) * 0.1
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let asset = AVURLAsset(url: url)
        print("Checking local WAV")
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        precondition(playable)
        precondition(abs(duration.seconds - 1) < 0.01)
        let bytes = try Data(contentsOf: url)
        let resource = StreamingAudioResource(fileSize: Int64(bytes.count), mimeType: "audio/wav") { offset, length in
            let start = Int(offset)
            let end = min(bytes.count, start + Int(length))
            return bytes.subdata(in: start..<end)
        }
        defer { resource.cancelAll() }
        let streamedAsset = AVURLAsset(url: URL(string: "telisten-stream://track/\(UUID()).wav")!)
        streamedAsset.resourceLoader.setDelegate(resource, queue: DispatchQueue(label: "wav-test-loader"))
        print("Checking streamed WAV")
        let streamPlayable = try await streamedAsset.load(.isPlayable)
        let streamDuration = try await streamedAsset.load(.duration)
        precondition(streamPlayable)
        precondition(abs(streamDuration.seconds - 1) < 0.01)
        print("PASS: WAV recognition, non-audio rejection, local and byte-range streaming PCM WAV, duration discovery")
    }
}
