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

            let validTaskCheck: (BGTaskRequest) -> Bool = { scheduledTask in
                guard let earliestBeginDate = scheduledTask.earliestBeginDate else { return false }

                return scheduledTask.identifier == Self.taskIdentifier
                    && earliestBeginDate > .now
            }

            guard !requests.contains(where: validTaskCheck) else {
                logger.debug("Task \(Self.taskIdentifier) already scheduled, skipping")
                return
            }

            let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
            request.earliestBeginDate = .init(timeIntervalSinceNow: earliestBegin)

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
