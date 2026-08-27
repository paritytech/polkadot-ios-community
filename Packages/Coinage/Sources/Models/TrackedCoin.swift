import Foundation
import Operation_iOS

/// A ``Coin`` paired with the durability overlay (``CoinageAssetState``) that determines its
/// balance and selection disposition. Assembled on read; never persisted as-is.
public struct TrackedCoin: Equatable, Sendable {
    public let coin: Coin
    public let state: CoinageAssetState

    public init(coin: Coin, state: CoinageAssetState) {
        self.coin = coin
        self.state = state
    }
}

extension TrackedCoin {
    /// Free of any local claim, present on chain, and young enough to spend. Necessary but not
    /// sufficient for selection — outer layers still apply recycler and locking concerns.
    var isSelectable: Bool {
        state.isFree && coin.isOnchain && coin.isAgeValidToSpend
    }

    /// Not on chain yet, but expected to arrive: the entry minting it has not resolved. Keeps a
    /// freshly-split change coin visible instead of vanishing for a whole mortality window.
    var isMinting: Bool {
        state.isFree && !coin.isOnchain && state.minterStatus?.isLive == true
    }

    /// On chain and free, but aged at/past `recycleAtAge` — due for recycling, not spendable.
    func isAwaitingRecycling(for recycleAtAge: Int16 = CoinageConstants.recycleAtAge) -> Bool {
        guard let age = coin.age else { return false }

        return state.isFree && coin.isOnchain && age >= recycleAtAge
    }
}

extension TrackedCoin: Operation_iOS.Identifiable {
    public var identifier: String {
        coin.identifier
    }
}
