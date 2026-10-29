import Foundation
import AsyncExtensions
import FoundationExt

protocol DeviceTransferSenderCoordinating: Sendable {
    var states: AnyAsyncSequence<DeviceTransferState> { get async }

    func confirm(_ request: DeviceTransferRequest) async
    func reject(_ request: DeviceTransferRequest) async
    func cancel() async
}

actor DeviceTransferSenderCoordinator {
    private let runFactory: DeviceTransferRunMaking
    private let processedStore: DeviceTransferProcessedStoring
    private let dateProvider: any DateProviding
    private let logger: LoggerProtocol

    private let subject = AsyncCurrentValueSubject<DeviceTransferState>(.idle)
    private var run: (any DeviceTransferRunning)?

    init(
        runFactory: DeviceTransferRunMaking,
        processedStore: DeviceTransferProcessedStoring,
        dateProvider: any DateProviding,
        logger: LoggerProtocol
    ) {
        self.runFactory = runFactory
        self.processedStore = processedStore
        self.dateProvider = dateProvider
        self.logger = logger
    }
}

extension DeviceTransferSenderCoordinator: DeviceTransferSenderCoordinating {
    var states: AnyAsyncSequence<DeviceTransferState> {
        subject.eraseToAnyAsyncSequence()
    }

    func confirm(_ request: DeviceTransferRequest) async {
        guard !subject.value.isRunning else { return }

        // Discovery only re-checks the age when a statement arrives, so the offer can be stale by now.
        guard await isFresh(request) else {
            update(.failed(.expired))
            return
        }

        do {
            try await processedStore.markProcessed(requestId: request.requestId, outcome: .accepted)
            let run = try runFactory.makeSenderRun(for: request)
            self.run = run
            update(.connecting)
            Task { await perform(run) }
        } catch {
            logger.error("Device transfer confirm failed: \(error)")
            update(.failed(.failed))
        }
    }

    func reject(_ request: DeviceTransferRequest) async {
        do {
            try await processedStore.markProcessed(requestId: request.requestId, outcome: .rejected)
            try await runFactory.sendRejection(for: request)
        } catch {
            logger.error("Device transfer reject failed: \(error)")
        }
    }

    func cancel() async {
        await run?.cancel()
    }
}

private extension DeviceTransferSenderCoordinator {
    func isFresh(_ request: DeviceTransferRequest) async -> Bool {
        let now = await dateProvider.read()
        let maxAge = UInt64(DeviceTransferConstants.statementLifetimeInSeconds.milliseconds)
        return UInt64(now.timeIntervalSince1970.milliseconds) <= request.createdAt + maxAge
    }

    func perform(_ run: any DeviceTransferRunning) async {
        do {
            try await run.run { [weak self] event in await self?.handle(event) }
            update(.completed)
        } catch {
            logger.error("Device transfer as sender ended: \(error)")
            update(.failed(DeviceTransferFailure(error)))
        }

        self.run = nil
    }

    func handle(_ event: DeviceTransferRunEvent) {
        if event == .channelOpened, subject.value == .connecting {
            update(.transferring)
        }
    }

    func update(_ state: DeviceTransferState) {
        guard subject.value != state else { return }
        subject.send(state)
    }
}
