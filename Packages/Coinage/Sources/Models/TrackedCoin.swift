import Foundation

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
