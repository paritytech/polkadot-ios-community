import Foundation

public protocol CoinRecycleSchedulerMaking: Actor {
    func makeScheduler() -> CoinRecycleTaskScheduling
}
