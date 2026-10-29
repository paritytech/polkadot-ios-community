import Foundation

enum DeviceTransferRunEvent: Equatable {
    case peerFound
    case channelOpened
    case progress(DeviceTransferProgress)
}

typealias DeviceTransferRunEventHandler = @Sendable (DeviceTransferRunEvent) -> Void

protocol DeviceTransferRunning: Sendable {
    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws
    func cancel() async
}

protocol DeviceTransferExchangeMaking: Sendable {
    func makeSenderConnection() -> DeviceTransferConnectionMaking
    func makeReceiverConnection(senderInstallationId: Data) -> DeviceTransferConnectionMaking
}

typealias DeviceTransferConnectionMaking = @Sendable (
    any DevicePeerConnectionFlowing,
    @escaping DeviceTransferRunEventHandler
) async throws -> Void

actor DeviceTransferRun {
    private let context: DeviceTransferPeerContext
    private let connection: DeviceTransferConnectionMaking

    private var currentFlow: (any DevicePeerConnectionFlowing)?
    private var runTask: Task<Void, Error>?

    init(context: DeviceTransferPeerContext, connection: @escaping DeviceTransferConnectionMaking) {
        self.context = context
        self.connection = connection
    }
}

extension DeviceTransferRun: DeviceTransferRunning {
    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws {
        let connection = connection
        let context = context

        let task = Task {
            try await context.run(onEvent: onEvent) { [weak self] flow in
                await self?.setCurrentFlow(flow)
                try await connection(flow, onEvent)
            }
        }
        runTask = task

        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() async {
        try? await currentFlow?.sendTransferControl(.abort(.userCancelled))
        runTask?.cancel()
    }
}

private extension DeviceTransferRun {
    func setCurrentFlow(_ flow: any DevicePeerConnectionFlowing) {
        currentFlow = flow
    }
}

extension DeviceTransferRunning {
    func run(handlingEventsWith handle: @escaping @Sendable (DeviceTransferRunEvent) async -> Void) async throws {
        let (events, continuation) = AsyncStream.makeStream(of: DeviceTransferRunEvent.self)
        let consumer = Task {
            for await event in events {
                await handle(event)
            }
        }

        do {
            try await run { continuation.yield($0) }
            continuation.finish()
            await consumer.value
        } catch {
            continuation.finish()
            await consumer.value
            throw error
        }
    }
}
