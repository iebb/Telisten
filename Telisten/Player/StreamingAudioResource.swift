@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

typealias AudioByteProvider = @Sendable (_ offset: Int64, _ length: Int32) async throws -> Data

private actor StreamWindow {
    private static let chunkSize: Int64 = 512 * 1_024
    private static let prefetchChunkCount = 4
    private static let maxConcurrentFetches = 4

    private let fileSize: Int64
    private let provider: AudioByteProvider
    private var chunks: [Int64: Data] = [:]
    private var chunkOrder: [Int64] = []
    private var requests: [Int64: Task<Data, Error>] = [:]

    init(fileSize: Int64, provider: @escaping AudioByteProvider) {
        self.fileSize = fileSize
        self.provider = provider
    }

    func bytes(at requestedOffset: Int64, length requestedLength: Int) async throws -> Data {
        guard requestedOffset >= 0, requestedOffset < fileSize, requestedLength > 0 else {
            return Data()
        }

        let length = Int(min(Int64(requestedLength), fileSize - requestedOffset))
        let firstChunk = requestedOffset - (requestedOffset % Self.chunkSize)
        let lastByte = requestedOffset + Int64(length) - 1
        let lastChunk = lastByte - (lastByte % Self.chunkSize)
        let requiredChunkCount = Int((lastChunk - firstChunk) / Self.chunkSize) + 1
        let fetchCount = max(requiredChunkCount, Self.prefetchChunkCount)

        var offsets: [Int64] = []
        offsets.reserveCapacity(fetchCount)
        for index in 0..<fetchCount {
            let offset = firstChunk + Int64(index) * Self.chunkSize
            guard offset < fileSize else { break }
            offsets.append(offset)
        }

        var fetched: [Int64: Data] = [:]
        var index = 0
        while index < offsets.count {
            let end = min(index + Self.maxConcurrentFetches, offsets.count)
            let batch = Array(offsets[index..<end])
            try await withThrowingTaskGroup(of: (Int64, Data).self) { group in
                for offset in batch {
                    group.addTask {
                        (offset, try await self.chunk(at: offset))
                    }
                }
                for try await (offset, data) in group {
                    fetched[offset] = data
                }
            }
            index = end
        }

        var result = Data()
        result.reserveCapacity(length)
        var offset = firstChunk
        var remaining = length
        var skip = Int(requestedOffset - firstChunk)
        while remaining > 0 {
            guard let chunk = fetched[offset] ?? chunks[offset] else {
                throw TransferError.incompleteData
            }
            guard skip < chunk.count else { throw TransferError.incompleteData }
            let count = min(remaining, chunk.count - skip)
            result.append(chunk.subdata(in: skip..<(skip + count)))
            remaining -= count
            offset += Self.chunkSize
            skip = 0
        }
        return result
    }

    private func chunk(at offset: Int64) async throws -> Data {
        if let data = chunks[offset] { return data }
        if let request = requests[offset] {
            return try await request.value
        }

        let provider = provider
        let length = Int32(min(Self.chunkSize, fileSize - offset))
        let request = Task<Data, Error> {
            try await provider(offset, length)
        }
        requests[offset] = request

        do {
            let data = try await request.value
            requests.removeValue(forKey: offset)
            guard data.count == Int(length) else { throw TransferError.incompleteData }
            chunks[offset] = data
            chunkOrder.removeAll { $0 == offset }
            chunkOrder.append(offset)
            while chunkOrder.count > Self.prefetchChunkCount * 2 {
                let evicted = chunkOrder.removeFirst()
                chunks.removeValue(forKey: evicted)
            }
            return data
        } catch {
            requests.removeValue(forKey: offset)
            throw error
        }
    }

    private enum TransferError: LocalizedError {
        case incompleteData

        var errorDescription: String? {
            "Telegram stopped sending this stream before the requested bytes arrived."
        }
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
