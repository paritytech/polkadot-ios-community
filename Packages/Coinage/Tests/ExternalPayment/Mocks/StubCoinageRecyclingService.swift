import Foundation
@testable import Coinage

/// Records the coins handed to `recycleCoins`; `error` makes the call throw.
actor StubCoinageRecyclingService: CoinageRecyclingServicing {
    private(set) var recycled: [[Coin]] = []
    private var error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func setError(_ error: Error?) {
        self.error = error
    }

    @discardableResult
    func recycleCoins(_ coins: [Coin]) async throws -> Int {
        recycled.append(coins)
        if let error { throw error }
        return coins.count
    }
}
