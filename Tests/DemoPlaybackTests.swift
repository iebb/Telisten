import AVFoundation
import Foundation

@main
@MainActor
enum DemoPlaybackTests {
    static func main() async throws {
        try testLaunchArguments()
        try testWAVHeaderAndDuration()
        try await testFileIsWrittenOnceAndDecodes()
        try await testLoopedAssetMatchesStatedDuration()
        print("PASS: TELISTEN_DEMO_ARGS launch arguments, demo WAV header/rate/duration/level, cached sample reuse, looped demo asset duration, demo playback through AudioPlayer")
    }

    static func testLaunchArguments() throws {
        let process = ["/Telisten", "-AppleLanguages", "(en)"]
        precondition(LaunchArguments.resolved(processArguments: process, environment: [:]) == process)
        let resolved = LaunchArguments.resolved(
            processArguments: process,
            environment: [LaunchArguments.environmentKey: "  --demo\t--demo-chat \n --demo-no-lyrics "]
        )
        precondition(resolved == process + ["--demo", "--demo-chat", "--demo-no-lyrics"])
        precondition(LaunchArguments.resolved(
            processArguments: process,
            environment: [LaunchArguments.environmentKey: "   "]
        ) == process)
    }

    static func testWAVHeaderAndDuration() throws {
        let data = DemoAudioSample.wavData(duration: 2, sampleRate: 22_050)
        let bytes = [UInt8](data)
        func text(_ offset: Int) -> String { String(decoding: bytes[offset..<offset + 4], as: UTF8.self) }
        func u32(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24 }
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        precondition(text(0) == "RIFF" && text(8) == "WAVE" && text(12) == "fmt " && text(36) == "data")
        precondition(u32(4) == bytes.count - 8, "RIFF chunk size")
        precondition(u32(16) == 16 && u16(20) == 1, "PCM fmt chunk")
        precondition(u16(22) == 1, "mono")
        precondition(u32(24) == 22_050, "sample rate")
        precondition(u32(28) == 44_100 && u16(32) == 2 && u16(34) == 16, "byte rate / block align / bits")
        precondition(u32(40) == 2 * 22_050 * 2 && bytes.count == 44 + 2 * 22_050 * 2, "two seconds of samples")

        let samples = DemoAudioSample.synthesize(
            frameCount: Int(DemoAudioSample.duration) * 8_000,
            sampleRate: 8_000
        )
        let peak = samples.map(abs).max() ?? 0
        precondition(peak > 0.05, "sample must be audible")
        precondition(peak < 0.95, "sample must not clip")
        precondition(abs(samples.first ?? 1) < 0.001 && abs(samples.last ?? 1) < 0.01, "fades in and out")
    }

    static func testFileIsWrittenOnceAndDecodes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("telisten-demo-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try DemoAudioSample.fileURL(in: directory)
        let firstDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try await Task.sleep(for: .milliseconds(20))
        let reused = try DemoAudioSample.fileURL(in: directory)
        precondition(reused == url)
        let secondDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        precondition(firstDate == secondDate, "a complete cached sample is reused")

        let file = try AVAudioFile(forReading: url)
        precondition(file.fileFormat.sampleRate == Double(DemoAudioSample.sampleRate))
        precondition(file.fileFormat.channelCount == 1)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        precondition(abs(seconds - DemoAudioSample.duration) < 0.01, "sample duration \(seconds)")
    }

    static func testLoopedAssetMatchesStatedDuration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("telisten-demo-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try DemoAudioSample.fileURL(in: directory)

        for stated in [271.0, 20.0, 64.5] {
            let asset = try await DemoAudioSample.loopedAsset(from: url, duration: stated)
            let duration = try await asset.load(.duration).seconds
            precondition(abs(duration - stated) < 0.01, "looped duration \(duration) for \(stated)")
        }

        let track = Track(documentID: 10_000, accessHash: 1, fileReference: Data(), dcID: 2,
                          messageID: 500, chatID: "c:1001", title: "Glass Horizon", artist: "Kitta Studio",
                          fileName: "Glass Horizon.m4a", mimeType: "audio/mp4", duration: 271,
                          size: 7_000_000, date: Date())
        let engine = AVPlayer()
        let player = AudioPlayer(player: engine, configureSystemPlayback: false)
        player.beginLoading(track)
        let asset = try await DemoAudioSample.loopedAsset(from: url, duration: track.duration)
        await player.loadDemo(track, asset: asset, autoplay: false, startingAt: 48)
        precondition(engine.currentItem?.status == .readyToPlay, "demo item becomes ready")
        precondition(abs(player.currentTime - 48) < 0.01 && player.duration == 271)
        try await Task.sleep(for: .milliseconds(300))
        let position = engine.currentTime().seconds
        precondition(abs(position - 48) < 0.5, "demo item starts at the previewed position, got \(position)")
        let itemDuration = try await engine.currentItem!.asset.load(.duration).seconds
        precondition(abs(itemDuration - 271) < 0.01)
        player.reset()
    }
}
