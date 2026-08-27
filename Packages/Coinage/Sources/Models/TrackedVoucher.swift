import Foundation
import Operation_iOS

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

extension TrackedVoucher {
    /// Free of any local claim and registered in the recycler on chain — offerable for selection,
    /// its effective privacy decided separately.
    var isSelectable: Bool {
        state.isFree && voucher.isInRecycler
    }

    /// Registered on chain and working its way into a ring: not usable yet, but it exists.
    var isOnboarding: Bool {
        state.isFree && voucher.remoteState == .onboarding
    }

    /// Nowhere on chain yet, but expected to arrive: the entry minting it has not resolved. The
    /// counterpart of ``TrackedCoin/isMinting``.
    var isMinting: Bool {
        state.isFree && voucher.remoteState == .unlocated && state.minterStatus?.isLive == true
    }
}

extension TrackedVoucher: Operation_iOS.Identifiable {
    public var identifier: String {
        voucher.identifier
    }
}
