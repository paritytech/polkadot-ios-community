import Foundation

/// Strategy 1: exact match. The coins are handed to the recipient as they are.
///
/// No extrinsic and therefore no entry: nothing is consumed or minted on chain. What the
/// wallet records is a handoff mark per coin, which is exactly what Appendix A reads to report
/// whether the payment was claimed.
struct ExactMatchStrategy: TransferStrategy {
    private let coins: [Coin]

    init(coins: [Coin]) {
        self.coins = coins
    }

    func run(context: TransferContext) async throws {
        guard !coins.isEmpty else {
            throw TransferStrategyError.emptyCoins
        }

        // No entry backs these coins, so nothing but this reservation keeps them out of a
        // concurrent selection before the handoff mark lands.
        try await context.reserve(coins: coins, vouchers: [])
        try await context.handOff(coins: coins)
        await context.settle()
    }
}
