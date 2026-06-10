import Foundation
import Coinage

actor CoinRecycleSchedulerFactory {
    private let logger: LoggerProtocol

    private var scheduler: CoinRecycleTaskScheduling?

    init(logger: LoggerProtocol) {
        self.logger = logger
    }
}

extension CoinRecycleSchedulerFactory: CoinRecycleSchedulerMaking {
    func makeScheduler() -> any CoinRecycleTaskScheduling {
        guard let scheduler else {
            let scheduler = CoinageRecyclingScheduler(
                logger: logger
            )
            self.scheduler = scheduler
            return scheduler
        }

        return scheduler
    }
}
