import Foundation
import FoundationExt

typealias DeviceSyncForegroundRecoveryHandler = @Sendable () async -> Void
typealias DeviceSyncForegroundEventStreamFactory = @Sendable () -> AsyncStream<Void>

actor DeviceSyncForegroundRecoveryController {
    private let foregroundEventStreamFactory: DeviceSyncForegroundEventStreamFactory
    private let logger: LoggerProtocol

    private var foregroundTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryHandler: DeviceSyncForegroundRecoveryHandler?

    init(
        applicationStateStreamFactory: ApplicationStateStreamFactory = ApplicationStateStreamFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        foregroundEventStreamFactory = {
            applicationStateStreamFactory.stream(for: .willEnterForeground)
        }
        self.logger = logger
    }

    init(
        foregroundEventStreamFactory: @escaping DeviceSyncForegroundEventStreamFactory,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.foregroundEventStreamFactory = foregroundEventStreamFactory
        self.logger = logger
    }

    func start(recoveryHandler: @escaping DeviceSyncForegroundRecoveryHandler) {
        self.recoveryHandler = recoveryHandler

        foregroundTask?.cancel()

        let foregroundEvents = foregroundEventStreamFactory()

        foregroundTask = Task { [weak self] in
            for await _ in foregroundEvents {
                guard !Task.isCancelled else { return }
                await self?.handleForegroundEvent()
            }
        }
    }

    func stop() {
        foregroundTask?.cancel()
        foregroundTask = nil

        recoveryTask?.cancel()
        recoveryTask = nil

        recoveryHandler = nil
    }

    private func handleForegroundEvent() {
        guard recoveryTask == nil else {
            logger.debug("Foreground recovery already in progress, skipping")
            return
        }

        guard let recoveryHandler else { return }

        recoveryTask = Task { [weak self, recoveryHandler] in
            await recoveryHandler()
            await self?.finishRecovery()
        }
    }

    private func finishRecovery() {
        recoveryTask = nil
    }
}
