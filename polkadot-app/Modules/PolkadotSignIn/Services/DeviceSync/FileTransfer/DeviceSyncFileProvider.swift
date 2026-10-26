import Foundation

protocol DeviceSyncFileProviding: Sendable {
    func handle(_ request: Chat.DeviceSyncFileMessage.Request) async
    func handle(_ request: Chat.DeviceSyncFileMessage.AvailabilityRequest) async
    func cancel(requestId: UInt32) async
    func close() async
}

/// Serves `device-sync-file` requests in arrival order, one at a time, one file at a time.
/// Every request ends with `completed`, including a cancelled one.
actor DeviceSyncFileProvider {
    static let chunkPayloadSize = 60 * 1_024

    private let flow: any DevicePeerConnectionFlowing
    private let locator: DeviceSyncFileLocating
    private let logger: LoggerProtocol

    private var pendingRequests: [Chat.DeviceSyncFileMessage.Request] = []
    private var currentRequestId: UInt32?
    private var cancelledRequestIds: Set<UInt32> = []
    private var servingTask: Task<Void, Never>?
    private var isClosed = false

    init(
        flow: any DevicePeerConnectionFlowing,
        locator: DeviceSyncFileLocating,
        logger: LoggerProtocol
    ) {
        self.flow = flow
        self.locator = locator
        self.logger = logger
    }
}

extension DeviceSyncFileProvider: DeviceSyncFileProviding {
    func handle(_ request: Chat.DeviceSyncFileMessage.Request) {
        guard !isClosed else { return }

        pendingRequests.append(request)
        startServingIfNeeded()
    }

    func handle(_ request: Chat.DeviceSyncFileMessage.AvailabilityRequest) async {
        guard !isClosed else { return }

        var availability: [Chat.DeviceSyncFileMessage.Availability] = []

        for file in request.files {
            switch await locator.locate(file) {
            case let .stored(_, size):
                availability.append(.available(totalSize: size))
            case let .unavailable(reason):
                availability.append(.unavailable(reason))
            }
        }

        let response = Chat.DeviceSyncFileMessage.AvailabilityResponse(
            requestId: request.requestId,
            availability: availability
        )

        await sendIgnoringFailure(.availabilityResponse(response))
    }

    func cancel(requestId: UInt32) async {
        guard !isClosed else { return }

        if currentRequestId == requestId {
            cancelledRequestIds.insert(requestId)
            return
        }

        guard let index = pendingRequests.firstIndex(where: { $0.requestId == requestId }) else {
            return
        }

        pendingRequests.remove(at: index)
        await sendIgnoringFailure(.completed(requestId: requestId))
    }

    func close() async {
        isClosed = true
        pendingRequests.removeAll()

        let task = servingTask
        servingTask = nil
        task?.cancel()
        await task?.value
    }
}

private extension DeviceSyncFileProvider {
    func startServingIfNeeded() {
        guard servingTask == nil else { return }

        servingTask = Task { [weak self] in
            await self?.servePendingRequests()
        }
    }

    func servePendingRequests() async {
        while !pendingRequests.isEmpty, !Task.isCancelled {
            let request = pendingRequests.removeFirst()
            currentRequestId = request.requestId

            do {
                try await serve(request)
            } catch {
                logger.error("Sync file request \(request.requestId) aborted: \(error)")
                pendingRequests.removeAll()
            }

            currentRequestId = nil
            cancelledRequestIds.remove(request.requestId)
        }

        servingTask = nil
    }

    func serve(_ request: Chat.DeviceSyncFileMessage.Request) async throws {
        for (index, item) in request.files.enumerated() {
            guard !isCancelled(request.requestId) else { break }

            try await serve(item, fileIndex: UInt32(index), requestId: request.requestId)
        }

        try await flow.sendFileMessage(.completed(requestId: request.requestId))
    }

    func serve(
        _ item: Chat.DeviceSyncFileMessage.RequestItem,
        fileIndex: UInt32,
        requestId: UInt32
    ) async throws {
        switch await locator.locate(item.file) {
        case let .unavailable(reason):
            try await sendUnavailable(reason, fileIndex: fileIndex, requestId: requestId)
        case let .stored(url, size):
            try await flow.sendFileMessage(.header(.init(requestId: requestId, fileIndex: fileIndex, totalSize: size)))

            let range = FileRange(url: url, offset: item.offset, size: size)
            let isComplete = try await streamChunks(of: range, fileIndex: fileIndex, requestId: requestId)

            if !isComplete, !isCancelled(requestId) {
                try await sendUnavailable(.notStored, fileIndex: fileIndex, requestId: requestId)
            }
        }
    }

    /// Returns `false` when the file can't be read up to its announced size (deleted or truncated meanwhile).
    func streamChunks(of range: FileRange, fileIndex: UInt32, requestId: UInt32) async throws -> Bool {
        guard range.offset < range.size else { return true }

        guard let handle = try? FileHandle(forReadingFrom: range.url) else { return false }
        defer { try? handle.close() }

        var offset = range.offset

        do {
            try handle.seek(toOffset: offset)
        } catch {
            return false
        }

        while offset < range.size {
            guard !isCancelled(requestId) else { return false }

            guard let data = try? handle.read(upToCount: Self.chunkPayloadSize), !data.isEmpty else {
                return false
            }

            let chunk = Chat.DeviceSyncFileMessage.Chunk(
                requestId: requestId,
                fileIndex: fileIndex,
                offset: offset,
                data: data
            )

            try await flow.sendFileMessage(.chunk(chunk))
            offset += UInt64(data.count)
        }

        return true
    }

    func sendUnavailable(
        _ reason: Chat.DeviceSyncFileMessage.UnavailableReason,
        fileIndex: UInt32,
        requestId: UInt32
    ) async throws {
        let unavailable = Chat.DeviceSyncFileMessage.Unavailable(
            requestId: requestId,
            fileIndex: fileIndex,
            reason: reason
        )
        try await flow.sendFileMessage(.unavailable(unavailable))
    }

    func sendIgnoringFailure(_ message: Chat.DeviceSyncFileMessage) async {
        do {
            try await flow.sendFileMessage(message)
        } catch {
            logger.error("Sync file message send failed: \(error)")
        }
    }

    func isCancelled(_ requestId: UInt32) -> Bool {
        cancelledRequestIds.contains(requestId)
    }
}

private struct FileRange {
    let url: URL
    let offset: UInt64
    let size: UInt64
}
