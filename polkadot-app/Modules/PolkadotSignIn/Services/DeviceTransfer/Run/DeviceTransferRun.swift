import Foundation

enum DeviceTransferRunEvent: Equatable {
    case peerFound
    case channelOpened
    case progress(DeviceTransferProgress)
}

typealias DeviceTransferRunEventHandler = @Sendable (DeviceTransferRunEvent) -> Void

protocol DeviceTransferClientProtocol {
    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws
}

protocol DeviceTransferRunning: Sendable {
    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws
    func cancel() async
}

enum DeviceTransferClientRole: Equatable {
    case sender
    case receiver(senderInstallationId: Data)
}

protocol DeviceTransferClientMaking: Sendable {
    func makeClient(
        for role: DeviceTransferClientRole,
        flow: any DevicePeerConnectionFlowing
    ) -> any DeviceTransferClientProtocol
}

actor DeviceTransferRun {
    private let context: DeviceTransferPeerContext
    private let clientFactory: DeviceTransferClientMaking
    private let role: DeviceTransferClientRole

    private var currentFlow: (any DevicePeerConnectionFlowing)?
    private var runTask: Task<Void, Error>?

    init(
        context: DeviceTransferPeerContext,
        clientFactory: DeviceTransferClientMaking,
        role: DeviceTransferClientRole
    ) {
        self.context = context
        self.clientFactory = clientFactory
        self.role = role
    }
}

extension DeviceTransferRun: DeviceTransferRunning {
    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws {
        let context = context
        let clientFactory = clientFactory
        let role = role

        let task = Task {
            try await context.run(onEvent: onEvent) { [weak self] flow in
                await self?.setCurrentFlow(flow)
                try await clientFactory.makeClient(for: role, flow: flow).run(onEvent: onEvent)
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
