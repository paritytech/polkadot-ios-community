import Foundation

public protocol CoinageRecyclingServicing: Actor {
    func scheduleRecycling() async

    /// Recycles the given coins into vouchers.
    /// - Parameter coins: The coins to recycle.
    func recycleCoins(_ coins: [Coin]) async throws
}
