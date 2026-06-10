import Foundation

public protocol CoinRecycleTaskScheduling {
    func schedule(earliestBegin: TimeInterval)
    func cancel()
}

public extension CoinRecycleTaskScheduling {
    static var taskIdentifier: String { "io.coinage.background.recycler.refresh" }
}
