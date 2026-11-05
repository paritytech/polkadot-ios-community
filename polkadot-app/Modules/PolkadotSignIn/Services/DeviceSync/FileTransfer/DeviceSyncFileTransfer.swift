import Foundation
import AsyncExtensions

protocol DeviceSyncFileTransferring: Sendable {
    func start() async
    func close() async
}

protocol DeviceSyncFileTransferMaking: Sendable {
    func makeTransfer(
        flow: any DevicePeerConnectionFlowing,
        peerLogger: LoggerProtocol
    ) -> any DeviceSyncFileTransferring
}

/// `device-sync-file` on one data channel: serves the sibling's requests and makes this side's requester
/// available to the app while the channel is open. Request ids are scoped to this lifetime.
actor DeviceSyncFileTransfer {
    private let connectionId = UUID()
    private let flow: any DevicePeerConnectionFlowing
    private let provider: any DeviceSyncFileProviding
    private let requester: any DeviceSyncFileRequesting
    private let registry: any DeviceSyncFileChannelRegistering
    private let peerLogger: LoggerProtocol

    private var routingTask: Task<Void, Never>?
    private var isClosed = false

    init(
        flow: any DevicePeerConnectionFlowing,
        provider: any DeviceSyncFileProviding,
        requester: any DeviceSyncFileRequesting,
        registry: any DeviceSyncFileChannelRegistering,
        peerLogger: LoggerProtocol
    ) {
        self.flow = flow
        self.provider = provider
        self.requester = requester
        self.registry = registry
        self.peerLogger = peerLogger
    }
}

extension DeviceSyncFileTransfer: DeviceSyncFileTransferring {
    func start() async {
        guard routingTask == nil, !isClosed else { return }

        let iterator = await flow.fileMessages.makeAsyncIterator()
        guard !isClosed else { return }

        routingTask = Task { [weak self] in
            await self?.routeMessages(from: iterator)
        }

        await registry.register(requester, connectionId: connectionId)

        // `close()` may have run while registering and found nothing to undo yet.
        if isClosed {
            routingTask?.cancel()
            routingTask = nil
            await registry.unregister(connectionId: connectionId)
        }
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true

        await registry.unregister(connectionId: connectionId)

        let routingTask = routingTask
        self.routingTask = nil
        routingTask?.cancel()

        await requester.close()
        await provider.close()
        await routingTask?.value
    }
}

private extension DeviceSyncFileTransfer {
    func routeMessages(from initialIterator: AnyAsyncIterator<Chat.DeviceSyncFileMessage>) async {
        var iterator = initialIterator

        while let message = try? await iterator.next() {
            guard !Task.isCancelled else { return }
            await route(message)
        }
    }

    func route(_ message: Chat.DeviceSyncFileMessage) async {
        switch message {
        case let .filesRequest(request):
            await provider.handle(request)
        case let .cancelFilesRequest(requestId):
            await provider.cancel(requestId: requestId)
        case let .availabilityRequest(request):
            await provider.handle(request)
        case .header,
             .chunk,
             .unavailable,
             .completed,
             .availabilityResponse:
            await requester.handle(message)
        }
    }
}

final class DeviceSyncFileTransferFactory: DeviceSyncFileTransferMaking {
    private let locator: DeviceSyncFileLocating
    private let downloadsStore: AttachmentStoring
    private let registry: any DeviceSyncFileChannelRegistering

    init(
        locator: DeviceSyncFileLocating,
        downloadsStore: AttachmentStoring,
        registry: any DeviceSyncFileChannelRegistering
    ) {
        self.locator = locator
        self.downloadsStore = downloadsStore
        self.registry = registry
    }

    func makeTransfer(
        flow: any DevicePeerConnectionFlowing,
        peerLogger: LoggerProtocol
    ) -> any DeviceSyncFileTransferring {
        DeviceSyncFileTransfer(
            flow: flow,
            provider: DeviceSyncFileProvider(flow: flow, locator: locator, logger: peerLogger),
            requester: DeviceSyncFileRequester(flow: flow, downloadsStore: downloadsStore, logger: peerLogger),
            registry: registry,
            peerLogger: peerLogger
        )
    }
}
