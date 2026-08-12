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
        ) { task in
            self.handleTask(task)
        }
    }
}

private extension CoinageRecyclingTaskRegistrator {
    func handleTask(_ task: BGTask) {
        logger.info("[BGTask] handler invoked for \(CoinageRecyclingScheduler.taskIdentifier)")

        let completed = OSAllocatedUnfairLock(initialState: false)

        let recyclingTask = Task { [logger, warmService = service] in
            let service: (any CoinageRecyclingServicing)? =
                if let warmService {
                    warmService
                } else {
                    await CoinageBackgroundBootstrap.makeRecyclingService(logger: logger)
                }

            guard let service else {
                logger.warning("[BGTask] \(CoinageRecyclingScheduler.taskIdentifier) no service available")
                self.finish(task, success: false, completed: completed)
                return
            }

            await service.scheduleRecycling()
            self.finish(task, success: true, completed: completed)
        }

        task.expirationHandler = { [logger] in
            logger.info("[BGTask] expiration handler fired for \(CoinageRecyclingScheduler.taskIdentifier)")
            recyclingTask.cancel()
            self.finish(task, success: false, completed: completed)
        }
    }

    func finish(
        _ task: BGTask,
        success: Bool,
        completed: OSAllocatedUnfairLock<Bool>
    ) {
        let alreadyCompleted = completed.withLock { current -> Bool in
            guard !current else { return true }
            current = true
            return false
        }

        guard !alreadyCompleted else { return }
        logger.info("[BGTask] \(CoinageRecyclingScheduler.taskIdentifier) completed, success: \(success)")
        task.setTaskCompleted(success: success)
    }
}
