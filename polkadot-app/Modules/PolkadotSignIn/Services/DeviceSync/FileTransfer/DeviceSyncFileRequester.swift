import Foundation

struct DeviceSyncFileRequestItem: Equatable {
    let file: Chat.DeviceSyncFileMessage.FileReference
    /// Name under which the completed file is stored in the downloads store.
    let filename: String
}

enum DeviceSyncFileRequestOutcome: Equatable {
    case completed
    case unavailable(Chat.DeviceSyncFileMessage.UnavailableReason)
    case sizeMismatch
    /// The request ended before the file finished; its partial bytes are kept for a later resume.
    case interrupted
}

protocol DeviceSyncFileRequesting: Sendable {
    /// Returns one outcome per item, in the same order.
    func request(_ items: [DeviceSyncFileRequestItem]) async -> [DeviceSyncFileRequestOutcome]
    func handle(_ message: Chat.DeviceSyncFileMessage) async
    func close() async
}

/// Requests files from the sibling on one data channel; request ids are unique for the channel's lifetime.
actor DeviceSyncFileRequester {
    static let defaultNoResponseTimeout: Duration = .seconds(30)

    private let flow: any DevicePeerConnectionFlowing
    private let downloadsStore: AttachmentStoring
    private let noResponseTimeout: Duration
    private let sleep: DeviceSyncSleep
    private let logger: LoggerProtocol

    private var nextRequestId: UInt32 = 0
    private var inFlight: [UInt32: InFlightRequest] = [:]
    private var isClosed = false

    init(
        flow: any DevicePeerConnectionFlowing,
        downloadsStore: AttachmentStoring,
        noResponseTimeout: Duration = DeviceSyncFileRequester.defaultNoResponseTimeout,
        sleep: @escaping DeviceSyncSleep = liveDeviceSyncSleep,
        logger: LoggerProtocol
    ) {
        self.flow = flow
        self.downloadsStore = downloadsStore
        self.noResponseTimeout = noResponseTimeout
        self.sleep = sleep
        self.logger = logger
    }
}

extension DeviceSyncFileRequester: DeviceSyncFileRequesting {
    func request(_ items: [DeviceSyncFileRequestItem]) async -> [DeviceSyncFileRequestOutcome] {
        guard !isClosed else { return items.map { _ in .interrupted } }
        guard !items.isEmpty else { return [] }

        let requestId = makeRequestId()
        let files = items.map { InFlightFile(item: $0, store: downloadsStore) }
        let wireRequest = Chat.DeviceSyncFileMessage.Request(
            requestId: requestId,
            files: files.map { .init(file: $0.item.file, offset: $0.writer.storedBytes()) }
        )

        return await withCheckedContinuation { continuation in
            inFlight[requestId] = InFlightRequest(files: files, continuation: continuation)
            startNoResponseTimeout(for: requestId)

            Task { await send(wireRequest) }
        }
    }

    func handle(_ message: Chat.DeviceSyncFileMessage) {
        switch message {
        case let .header(header):
            handleHeader(header)
        case let .chunk(chunk):
            handleChunk(chunk)
        case let .unavailable(unavailable):
            resolveFile(unavailable.fileIndex, of: unavailable.requestId, with: .unavailable(unavailable.reason))
        case let .completed(requestId):
            finishRequest(requestId, remaining: .interrupted)
        case .filesRequest,
             .cancelFilesRequest,
             .availabilityRequest,
             .availabilityResponse:
            break
        }
    }

    func close() {
        isClosed = true
        Array(inFlight.keys).forEach { finishRequest($0, remaining: .interrupted) }
    }
}

private extension DeviceSyncFileRequester {
    func makeRequestId() -> UInt32 {
        defer { nextRequestId &+= 1 }
        return nextRequestId
    }

    func send(_ request: Chat.DeviceSyncFileMessage.Request) async {
        do {
            try await flow.sendFileMessage(.filesRequest(request))
        } catch {
            logger.error("Sync file request \(request.requestId) send failed: \(error)")
            finishRequest(request.requestId, remaining: .interrupted)
        }
    }

    func startNoResponseTimeout(for requestId: UInt32) {
        let timeout = noResponseTimeout
        let sleep = sleep

        inFlight[requestId]?.timeoutTask = Task { [weak self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }

            await self?.handleNoResponse(for: requestId)
        }
    }

    func handleNoResponse(for requestId: UInt32) {
        guard inFlight[requestId]?.hasResponse == false else { return }

        logger.warning("Sync file request \(requestId) got no response, treating files as not stored")
        finishRequest(requestId, remaining: .unavailable(.notStored))
    }

    func markResponse(for requestId: UInt32) {
        guard inFlight[requestId]?.hasResponse == false else { return }

        inFlight[requestId]?.hasResponse = true
        inFlight[requestId]?.timeoutTask?.cancel()
    }

    func handleHeader(_ header: Chat.DeviceSyncFileMessage.Header) {
        guard let file = inFlight[header.requestId]?.file(at: header.fileIndex), file.outcome == nil else {
            return
        }

        markResponse(for: header.requestId)
        inFlight[header.requestId]?.files[Int(header.fileIndex)].totalSize = header.totalSize

        if file.writer.storedBytes() >= header.totalSize {
            completeFile(header.fileIndex, of: header.requestId, totalSize: header.totalSize)
        }
    }

    func handleChunk(_ chunk: Chat.DeviceSyncFileMessage.Chunk) {
        guard
            let file = inFlight[chunk.requestId]?.file(at: chunk.fileIndex),
            file.outcome == nil,
            let totalSize = file.totalSize
        else {
            return
        }

        do {
            try file.writer.write(chunk.data, at: chunk.offset)
        } catch {
            logger.error("Sync file chunk rejected: \(error)")
            file.writer.discard()
            resolveFile(chunk.fileIndex, of: chunk.requestId, with: .sizeMismatch)
            return
        }

        if file.writer.storedBytes() >= totalSize {
            completeFile(chunk.fileIndex, of: chunk.requestId, totalSize: totalSize)
        }
    }

    func completeFile(_ fileIndex: UInt32, of requestId: UInt32, totalSize: UInt64) {
        guard let file = inFlight[requestId]?.file(at: fileIndex) else { return }

        do {
            try file.writer.finish(totalSize: totalSize)
            resolveFile(fileIndex, of: requestId, with: .completed)
        } catch {
            logger.error("Sync file \(file.writer.filename) could not be finished: \(error)")
            resolveFile(fileIndex, of: requestId, with: .sizeMismatch)
        }
    }

    func resolveFile(_ fileIndex: UInt32, of requestId: UInt32, with outcome: DeviceSyncFileRequestOutcome) {
        guard let file = inFlight[requestId]?.file(at: fileIndex), file.outcome == nil else { return }

        markResponse(for: requestId)
        file.writer.closeHandle()
        inFlight[requestId]?.files[Int(fileIndex)].outcome = outcome
    }

    func finishRequest(_ requestId: UInt32, remaining: DeviceSyncFileRequestOutcome) {
        guard let request = inFlight.removeValue(forKey: requestId) else { return }

        request.timeoutTask?.cancel()

        let outcomes = request.files.map { file in
            file.writer.closeHandle()
            return file.outcome ?? remaining
        }

        request.continuation.resume(returning: outcomes)
    }
}

private struct InFlightFile {
    let item: DeviceSyncFileRequestItem
    let writer: DeviceSyncFileWriter
    var totalSize: UInt64?
    var outcome: DeviceSyncFileRequestOutcome?

    init(item: DeviceSyncFileRequestItem, store: AttachmentStoring) {
        self.item = item
        writer = DeviceSyncFileWriter(filename: item.filename, store: store)
    }
}

private struct InFlightRequest {
    var files: [InFlightFile]
    let continuation: CheckedContinuation<[DeviceSyncFileRequestOutcome], Never>
    var timeoutTask: Task<Void, Never>?
    var hasResponse = false

    func file(at index: UInt32) -> InFlightFile? {
        files.indices.contains(Int(index)) ? files[Int(index)] : nil
    }
}
