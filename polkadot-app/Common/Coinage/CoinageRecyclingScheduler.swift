import Foundation
import Coinage
import BackgroundTasks
import os

final class CoinageRecyclingScheduler {
    private let logger: LoggerProtocol

    init(logger: LoggerProtocol) {
        self.logger = logger
    }
}

// MARK: - CoinRecycleTaskScheduling

extension CoinageRecyclingScheduler: CoinRecycleTaskScheduling {
    func schedule(earliestBegin: TimeInterval) {
        BGTaskScheduler.shared.getPendingTaskRequests { [weak self] requests in
            guard let self else { return }

            let alreadyScheduled = requests.contains { $0.identifier == Self.taskIdentifier }

            guard !alreadyScheduled else {
                logger.debug("Task \(Self.taskIdentifier) already scheduled, skipping")
                return
            }

            let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
            request.earliestBeginDate = .init(timeIntervalSinceNow: earliestBegin)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false

            do {
                try BGTaskScheduler.shared.submit(request)
                logger.info(
                    "[BGTask] submitted request \(Self.taskIdentifier), earliestBeginDate: \(request.earliestBeginDate?.description ?? "nil")"
                )
            } catch {
                logger.error("[BGTask] submit failed for \(Self.taskIdentifier): \(error)")
            }
        }
    }

    func cancel() {
        logger.info("[BGTask] cancelling pending request \(Self.taskIdentifier)")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }
}
