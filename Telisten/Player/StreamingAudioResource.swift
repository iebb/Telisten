@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

typealias AudioByteProvider = @Sendable (_ offset: Int64, _ length: Int32) async throws -> Data

private actor StreamWindow {
    private static let preferredSize = 512 * 1_024

    private let fileSize: Int64
    private let provider: AudioByteProvider
    private var offset: Int64 = 0
    private var data = Data()

    init(fileSize: Int64, provider: @escaping AudioByteProvider) {
        self.fileSize = fileSize
        self.provider = provider
    }

    func bytes(at requestedOffset: Int64, length requestedLength: Int) async throws -> Data {
        guard requestedOffset >= 0, requestedOffset < fileSize, requestedLength > 0 else {
            return Data()
        }

        let length = Int(min(Int64(requestedLength), fileSize - requestedOffset))
        let cachedEnd = offset + Int64(data.count)
        if requestedOffset >= offset, requestedOffset + Int64(length) <= cachedEnd {
            let start = Int(requestedOffset - offset)
            return data.subdata(in: start..<(start + length))
        }

        let fetchLength = Int32(min(
            Int64(Int32.max),
            min(fileSize - requestedOffset, Int64(max(length, Self.preferredSize)))
        ))
        let fresh = try await provider(requestedOffset, fetchLength)
        offset = requestedOffset
        data = fresh
        return Data(fresh.prefix(length))
    }
}

final class StreamingAudioResource: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private static let responseSize = 256 * 1_024

    private let fileSize: Int64
    private let contentType: String
    private let window: StreamWindow
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(fileSize: Int64, mimeType: String, provider: @escaping AudioByteProvider) {
        self.fileSize = fileSize
        contentType = UTType(mimeType: mimeType)?.identifier ?? UTType.audio.identifier
        window = StreamWindow(fileSize: fileSize, provider: provider)
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let information = loadingRequest.contentInformationRequest {
            information.contentType = contentType
            information.contentLength = fileSize
            information.isByteRangeAccessSupported = true
        }

        guard let request = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }

        let identifier = ObjectIdentifier(loadingRequest)
        let task = Task { [weak self, weak loadingRequest] in
            guard let self, let loadingRequest else { return }
            do {
                var offset = request.currentOffset > 0 ? request.currentOffset : request.requestedOffset
                let available = max(0, fileSize - offset)
                var remaining = request.requestsAllDataToEndOfResource
                    ? available
                    : min(available, Int64(request.requestedLength))

                while remaining > 0 {
                    try Task.checkCancellation()
                    let length = Int(min(remaining, Int64(Self.responseSize)))
                    let bytes = try await window.bytes(at: offset, length: length)
                    guard !bytes.isEmpty else { break }
                    request.respond(with: bytes)
                    offset += Int64(bytes.count)
                    remaining -= Int64(bytes.count)
                }
                loadingRequest.finishLoading()
            } catch is CancellationError {
                loadingRequest.finishLoading(with: URLError(.cancelled))
            } catch {
                loadingRequest.finishLoading(with: error)
            }
            removeTask(identifier)
        }
        store(task, for: identifier)
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        takeTask(for: ObjectIdentifier(loadingRequest))?.cancel()
    }

    func cancelAll() {
        lock.lock()
        let current = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        current.forEach { $0.cancel() }
    }

    private func store(_ task: Task<Void, Never>, for identifier: ObjectIdentifier) {
        lock.lock()
        tasks[identifier] = task
        lock.unlock()
    }

    private func takeTask(for identifier: ObjectIdentifier) -> Task<Void, Never>? {
        lock.lock()
        let task = tasks.removeValue(forKey: identifier)
        lock.unlock()
        return task
    }

    private func removeTask(_ identifier: ObjectIdentifier) {
        _ = takeTask(for: identifier)
    }
}
