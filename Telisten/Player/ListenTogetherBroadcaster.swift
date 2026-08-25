@preconcurrency import AVFoundation
import Foundation
import HaishinKit
import RTMPHaishinKit

actor ListenTogetherBroadcaster {
    private var connection: RTMPConnection?
    private var stream: RTMPStream?
    private var feedTask: Task<Void, Never>?
    private var lastError: String?

    var isConnected: Bool { connection != nil && stream != nil }

    func connect(to endpoint: GroupCallPublishEndpoint) async throws {
        await disconnect()
        let connection = RTMPConnection(
            fourCcList: nil,
            videoFourCcInfoMap: nil,
            audioFourCcInfoMap: nil,
            capsEx: 0
        )
        let stream = RTMPStream(connection: connection)
        try await stream.setAudioSettings(
            AudioCodecSettings(
                bitRate: 128_000,
                downmix: true,
                sampleRate: 48_000,
                format: .aac
            )
        )
        _ = try await connection.connect(endpoint.url)
        _ = try await stream.publish(endpoint.key)
        self.connection = connection
        self.stream = stream
        lastError = nil
    }

    func play(_ fileURL: URL, from seconds: TimeInterval) {
        feedTask?.cancel()
        guard let stream else { return }
        feedTask = Task { [weak self] in
            do {
                try await Self.feed(fileURL, from: seconds, into: stream)
            } catch is CancellationError {
                return
            } catch {
                await self?.record(error)
            }
        }
    }

    func pause() {
        feedTask?.cancel()
        feedTask = nil
    }

    func disconnect() async {
        feedTask?.cancel()
        feedTask = nil
        if let stream { _ = try? await stream.close() }
        if let connection { try? await connection.close() }
        stream = nil
        connection = nil
    }

    func consumeError() -> String? {
        defer { lastError = nil }
        return lastError
    }

    private func record(_ error: Error) {
        lastError = "The group audio stream stopped. \(error.localizedDescription)"
    }

    private static func feed(
        _ fileURL: URL,
        from seconds: TimeInterval,
        into stream: RTMPStream
    ) async throws {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let sampleRate = max(format.sampleRate, 1)
        file.framePosition = min(
            max(0, AVAudioFramePosition(seconds * sampleRate)),
            file.length
        )

        let capacity: AVAudioFrameCount = 2_048
        var outputFrame: AVAudioFramePosition = 0
        while !Task.isCancelled, file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try file.read(into: buffer, frameCount: capacity)
            guard buffer.frameLength > 0 else { break }
            await stream.append(
                buffer,
                when: AVAudioTime(sampleTime: outputFrame, atRate: sampleRate)
            )
            outputFrame += AVAudioFramePosition(buffer.frameLength)
            let nanoseconds = UInt64((Double(buffer.frameLength) / sampleRate) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }
}
