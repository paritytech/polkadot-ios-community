import Foundation

/// A ``Voucher`` paired with the durability overlay (``CoinageAssetState``) that determines its
/// balance and selection disposition. Assembled on read; never persisted as-is.
public struct TrackedVoucher: Equatable {
    public let voucher: Voucher
    public let state: CoinageAssetState

    public init(voucher: Voucher, state: CoinageAssetState) {
        self.voucher = voucher
        self.state = state
    }
}
