@preconcurrency import AVFAudio
import Foundation
import HPRTMP

private final class AudioFileConversionSource: @unchecked Sendable {
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var reachedEnd = false
    private var readError: Error?

    init(file: AVAudioFile, format: AVAudioFormat) {
        self.file = file
        self.format = format
    }

    func read(
        _ requestedFrames: AVAudioFrameCount,
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !reachedEnd else {
            status.pointee = .endOfStream
            return nil
        }
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: requestedFrames) else {
            readError = CocoaError(.fileReadCorruptFile)
            reachedEnd = true
            status.pointee = .endOfStream
            return nil
        }
        do {
            try file.read(into: input, frameCount: requestedFrames)
        } catch {
            readError = error
            reachedEnd = true
            status.pointee = .endOfStream
            return nil
        }
        guard input.frameLength > 0 else {
            reachedEnd = true
            status.pointee = .endOfStream
            return nil
        }
        status.pointee = .haveData
        return input
    }

    func error() -> Error? {
        lock.withLock { readError }
    }

    func isFinished() -> Bool {
        lock.withLock { reachedEnd }
    }
}

actor ListenTogetherBroadcaster {
    private enum BroadcastError: LocalizedError {
        case invalidEndpoint
        case encoderUnavailable
        case publishFailed(String)
        case publishTimedOut

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                "Telegram returned an invalid group audio stream address."
            case .encoderUnavailable:
                "This track could not be prepared for group audio streaming."
            case let .publishFailed(message):
                "The group audio stream could not start. \(message)"
            case .publishTimedOut:
                "Telegram did not start the group audio stream in time."
            }
        }
    }

    private static let sampleRate = 48_000.0
    private static let bitRate = 128_000
    private static let channels: AVAudioChannelCount = 2
    private static let framesPerPacket: AVAudioFrameCount = 1_024
    private static let audioTag: UInt8 = 0xAF

    private var session: RTMPPublishSession?
    private var feedTask: Task<Void, Never>?
    private var lastError: String?

    var isConnected: Bool { session != nil }

    func connect(to endpoint: GroupCallPublishEndpoint) async throws {
        await disconnect()
        guard let publishURL = Self.publishURL(endpoint) else {
            throw BroadcastError.invalidEndpoint
        }

        let session = RTMPPublishSession()
        self.session = session
        let configuration = PublishConfigure(
            width: 0,
            height: 0,
            videocodecid: 0,
            audiocodecid: 10,
            framerate: 0,
            videoDatarate: nil,
            audioDatarate: Self.bitRate / 1_000,
            audioSamplerate: Int(Self.sampleRate)
        )
        await session.publish(url: publishURL, configure: configuration)
        try await waitUntilPublishing(session)
        await session.publishAudioHeader(data: Self.aacSequenceHeader)
        lastError = nil
    }

    func play(_ fileURL: URL, from seconds: TimeInterval) {
        feedTask?.cancel()
        guard let session else { return }
        feedTask = Task { [weak self] in
            do {
                try await Self.feed(fileURL, from: seconds, into: session)
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
        if let session { await session.stop() }
        session = nil
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
        into session: RTMPPublishSession
    ) async throws {
        let file = try AVAudioFile(forReading: fileURL)
        let inputFormat = file.processingFormat
        let inputSampleRate = max(inputFormat.sampleRate, 1)
        file.framePosition = min(
            max(0, AVAudioFramePosition(seconds * inputSampleRate)),
            file.length
        )

        guard let outputFormat = makeAACFormat(),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw BroadcastError.encoderUnavailable
        }
        converter.bitRate = Self.bitRate
        converter.downmix = true
        let source = AudioFileConversionSource(file: file, format: inputFormat)

        var packetIndex: UInt64 = 0
        while !Task.isCancelled {
            let output = AVAudioCompressedBuffer(
                format: outputFormat,
                packetCapacity: 1,
                maximumPacketSize: 4_096
            )

            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { requestedFrames, inputStatus in
                source.read(requestedFrames, status: inputStatus)
            }

            if let readError = source.error() { throw readError }
            if let conversionError { throw conversionError }

            switch status {
            case .haveData where output.byteLength > 0:
                var payload = Data([Self.audioTag, 0x01])
                payload.append(Data(bytes: output.data, count: Int(output.byteLength)))
                let timestamp = UInt32(
                    min(
                        UInt64(UInt32.max),
                        (packetIndex * UInt64(Self.framesPerPacket) * 1_000)
                            / UInt64(Self.sampleRate)
                    )
                )
                await session.publishAudio(data: payload, timestamp: timestamp)
                packetIndex += 1
                let nanoseconds = UInt64(
                    (Double(Self.framesPerPacket) / Self.sampleRate) * 1_000_000_000
                )
                try await Task.sleep(nanoseconds: nanoseconds)
            case .endOfStream:
                return
            case .error:
                throw conversionError ?? BroadcastError.encoderUnavailable
            case .inputRanDry:
                if source.isFinished() { return }
            default:
                break
            }
        }
    }

    private func waitUntilPublishing(_ session: RTMPPublishSession) async throws {
        switch await session.publishStatus {
        case .publishStart:
            return
        case let .failed(error):
            throw BroadcastError.publishFailed(String(describing: error))
        default:
            break
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await status in await session.statusStream {
                    switch status {
                    case .publishStart:
                        return
                    case let .failed(error):
                        throw BroadcastError.publishFailed(String(describing: error))
                    case .disconnected:
                        throw BroadcastError.publishFailed("The connection closed.")
                    default:
                        continue
                    }
                }
                throw BroadcastError.publishFailed("The connection closed.")
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw BroadcastError.publishTimedOut
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    private static var aacSequenceHeader: Data {
        // FLV AAC sequence header followed by AudioSpecificConfig:
        // AAC-LC, 48 kHz, stereo.
        Data([audioTag, 0x00, 0x11, 0x90])
    }

    private static func makeAACFormat() -> AVAudioFormat? {
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo) else {
            return nil
        }
        return AVAudioFormat(streamDescription: &description, channelLayout: layout)
    }

    private static func publishURL(_ endpoint: GroupCallPublishEndpoint) -> String? {
        guard let base = URL(string: endpoint.url),
              let scheme = base.scheme?.lowercased(),
              scheme == "rtmp" || scheme == "rtmps",
              !endpoint.key.isEmpty else {
            return nil
        }
        return endpoint.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/"
            + endpoint.key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
