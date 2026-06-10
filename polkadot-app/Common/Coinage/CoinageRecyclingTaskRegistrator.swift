import BackgroundTasks
import Coinage
import os

final class CoinageRecyclingTaskRegistrator {
    static let shared = CoinageRecyclingTaskRegistrator()

    weak var service: (any CoinageRecyclingServicing)?

    private let logger: LoggerProtocol = Logger.shared

    private init() {}

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: CoinageRecyclingScheduler.taskIdentifier,
            using: .main
        ) { [weak self] task in
            self?.handleTask(task)
        }
    }

    private func handleTask(_ task: BGTask) {
        logger.info("[BGTask] handler invoked for \(CoinageRecyclingScheduler.taskIdentifier)")

        guard let service else {
            logger.warning(
                "[BGTask] \(CoinageRecyclingScheduler.taskIdentifier) no service available, completing with failure"
            )
            task.setTaskCompleted(success: false)
            return
        }

        let completed = OSAllocatedUnfairLock(initialState: false)

        let recyclingTask = Task { [logger] in
            await service.scheduleRecycling()

            let alreadyCompleted = completed.withLock { current -> Bool in
                guard !current else { return true }
                current = true
                return false
            }

            guard !alreadyCompleted else { return }
            logger.info("[BGTask] \(CoinageRecyclingScheduler.taskIdentifier) completed, success: true")
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = { [logger] in
            logger.info("[BGTask] expiration handler fired for \(CoinageRecyclingScheduler.taskIdentifier)")

            let alreadyCompleted = completed.withLock { current -> Bool in
                guard !current else { return true }
                current = true
                return false
            }

            guard !alreadyCompleted else { return }
            recyclingTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
