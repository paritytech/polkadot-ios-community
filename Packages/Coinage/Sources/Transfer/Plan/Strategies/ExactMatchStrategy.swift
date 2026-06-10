import Foundation

/// Strategy 1: Exact match. Coins are simply passed through, no transaction
struct ExactMatchStrategy: TransferStrategy {
    private let coins: [Coin]

    init(coins: [Coin]) {
        self.coins = coins
    }

    func run(context: TransferContext) async throws {
        guard !coins.isEmpty else {
            throw TransferStrategyError.emptyCoins
        }

        // No extrinsic submission for exact match, but still persist state
        try await context.process(spentCoins: coins, destinationCoins: [])
    }
}
