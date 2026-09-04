import Foundation

/// Submits recycling for the given coins. The recycling *decision* lives in `CoinRecyclingEvaluator`;
/// this service only performs the submission, one `loadRecyclerWithCoin` extrinsic per coin.
public protocol CoinageRecyclingServicing: Actor {
    /// Recycles the given coins into vouchers. Coins whose ledger state is not free are skipped.
    func recycleCoins(_ coins: [Coin]) async throws
}
