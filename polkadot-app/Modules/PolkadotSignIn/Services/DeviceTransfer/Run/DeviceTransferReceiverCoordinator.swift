import Foundation
import AsyncExtensions
import StructuredConcurrency

protocol DeviceTransferFinalizing: Sendable {
    /// Takes over once the data is in: the steps after the run (DT11).
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

/// The new phone's side: publishes a request, waits for the old phone, runs the transfer and finalizes.
actor DeviceTransferReceiverCoordinator {
    static let activeInstallationTimeout: Duration = .seconds(30)

    private let publisher: DeviceTransferRequestPublishing
    private let installationObserver: CurrentInstallationObserving
    private let runFactory: DeviceTransferRunMaking
    private let finalizer: DeviceTransferFinalizing
    private let logger: LoggerProtocol

    private let subject = AsyncCurrentValueSubject<DeviceTransferState>(.idle)
    private var run: (any DeviceTransferRunning)?
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
        update(.waitingForSender)

        do {
            let senderInstallationId = try await activeInstallationId()
            let request = try await publisher.publishRequest(configuration: configuration)
            published = (request, configuration)

            let run = try runFactory.makeReceiverRun(for: request, senderInstallationId: senderInstallationId)
            self.run = run
            Task { await perform(run, for: request) }
        } catch {
            logger.error("Device transfer request failed: \(error)")
            update(.failed(.failed))
        }
    }

    func cancel() async {
        await run?.cancel()

        guard let published else { return }

        do {
            try await publisher.cancel(requestId: published.request.requestId, configuration: published.configuration)
        } catch {
            logger.error("Device transfer request cancel failed: \(error)")
        }
    }
}

private extension DeviceTransferReceiverCoordinator {
    /// The checkpoint belongs to the old phone, which the active installation record names.
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

    func perform(_ run: any DeviceTransferRunning, for request: DeviceTransferRequest) async {
        do {
            try await run.run { [weak self] event in await self?.handle(event) }
            update(.finalizing)
            try await finalizer.finalize(after: request)
            update(.completed)
        } catch {
            logger.error("Device transfer as receiver ended: \(error)")
            update(.failed(DeviceTransferFailure(error)))
        }

        self.run = nil
        published = nil
    }

    func handle(_ event: DeviceTransferRunEvent) {
        switch event {
        case .peerFound:
            if subject.value == .waitingForSender {
                update(.connecting)
            }
        case .channelOpened:
            break
        case let .progress(.syncing(applied, total)):
            update(.syncing(applied: applied, total: total))
        case let .progress(.files(progress)):
            update(.files(progress))
        }
    }

    func update(_ state: DeviceTransferState) {
        guard subject.value != state else { return }
        subject.send(state)
    }
}
