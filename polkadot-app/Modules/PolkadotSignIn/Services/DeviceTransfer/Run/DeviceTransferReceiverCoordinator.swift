import Foundation
import AsyncExtensions
import StructuredConcurrency

protocol DeviceTransferFinalizing: Sendable {
    func finalize(after request: DeviceTransferRequest) async throws
}

protocol DeviceTransferReceiverCoordinating: Sendable {
    var states: AnyAsyncSequence<DeviceTransferState> { get async }

    func start(configuration: DeviceTransferDiscoveryConfiguration) async
    func cancel() async
}

enum DeviceTransferReceiverError: Error {
    case activeInstallationUnknown
}

actor DeviceTransferReceiverCoordinator {
    static let activeInstallationTimeout: Duration = .seconds(30)

    private let publisher: DeviceTransferRequestPublishing
    private let installationObserver: CurrentInstallationObserving
    private let runFactory: DeviceTransferRunMaking
    private let finalizer: DeviceTransferFinalizing
    private let logger: LoggerProtocol

    private let subject = AsyncCurrentValueSubject<DeviceTransferState>(.idle)
    private var run: (any DeviceTransferRunning)?
    private var transferTask: Task<Void, Never>?
    private var hasPeerAnswered = false
    private var published: (request: DeviceTransferRequest, configuration: DeviceTransferDiscoveryConfiguration)?

    init(
        publisher: DeviceTransferRequestPublishing,
        installationObserver: CurrentInstallationObserving,
        runFactory: DeviceTransferRunMaking,
        finalizer: DeviceTransferFinalizing,
        logger: LoggerProtocol
    ) {
        self.publisher = publisher
        self.installationObserver = installationObserver
        self.runFactory = runFactory
        self.finalizer = finalizer
        self.logger = logger
    }
}

extension DeviceTransferReceiverCoordinator: DeviceTransferReceiverCoordinating {
    var states: AnyAsyncSequence<DeviceTransferState> {
        subject.eraseToAnyAsyncSequence()
    }

    func start(configuration: DeviceTransferDiscoveryConfiguration) async {
        guard !subject.value.isRunning else { return }
        hasPeerAnswered = false
        update(.waitingForSender)

        do {
            let senderInstallationId = try await activeInstallationId()
            transferTask = Task { await perform(configuration: configuration, from: senderInstallationId) }
        } catch {
            logger.error("Device transfer request failed: \(error)")
            update(.failed(.failed))
        }
    }

    func cancel() async {
        await run?.cancel()
        transferTask?.cancel()

        guard let published else { return }

        do {
            try await publisher.cancel(requestId: published.request.requestId, configuration: published.configuration)
        } catch {
            logger.error("Device transfer request cancel failed: \(error)")
        }
    }
}

private extension DeviceTransferReceiverCoordinator {
    /// The checkpoint is keyed by the old phone, which only the active installation record names.
    func activeInstallationId() async throws -> Data {
        let statuses = await installationObserver.statusStream

        return try await withTimeout(Self.activeInstallationTimeout) {
            for try await status in statuses {
                if case let .inactive(installation) = status {
                    return installation.installationId
                }
            }
            throw DeviceTransferReceiverError.activeInstallationUnknown
        }
    }

    func perform(configuration: DeviceTransferDiscoveryConfiguration, from senderInstallationId: Data) async {
        do {
            let request = try await runUntilFinished(configuration: configuration, from: senderInstallationId)
            update(.finalizing)
            try await finalizer.finalize(after: request)
            update(.completed)
        } catch {
            logger.error("Device transfer as receiver ended: \(error)")
            update(.failed(DeviceTransferFailure(error)))
        }

        run = nil
        published = nil
        transferTask = nil
    }

    /// A request lives as long as the idle limit, so a run that reaches it publishes a new request
    /// and resumes from the checkpoint.
    func runUntilFinished(
        configuration: DeviceTransferDiscoveryConfiguration,
        from senderInstallationId: Data
    ) async throws -> DeviceTransferRequest {
        while true {
            try Task.checkCancellation()

            let request = try await publisher.publishRequest(configuration: configuration)
            published = (request, configuration)
            let run = try runFactory.makeReceiverRun(for: request, senderInstallationId: senderInstallationId)
            self.run = run

            do {
                try await run.run { [weak self] event in await self?.handle(event) }
                return request
            } catch DeviceTransferContextError.idleTimeout {
                logger.info("Device transfer request reached the idle limit, publishing a new one")
                update(hasPeerAnswered ? .reconnecting : .waitingForSender)
            }
        }
    }

    func handle(_ event: DeviceTransferRunEvent) {
        if event == .peerFound {
            hasPeerAnswered = true
        }

        if let next = subject.value.next(after: event) {
            update(next)
        }
    }

    func update(_ state: DeviceTransferState) {
        guard subject.value != state else { return }
        subject.send(state)
    }
}
