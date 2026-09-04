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

    /// Nowhere on chain yet, but nothing has proven the entry minting it never ran. The
    /// counterpart of ``TrackedCoin/isMinting``. Finality still counts: the mint is then most
    /// certainly done, and only the location the chain reports is behind.
    var isMinting: Bool {
        state.isFree && voucher.remoteState == .unlocated && state.minterStatus?.canArrive == true
    }

    /// Whether this voucher contributes to the displayed balance — selectable (spendable/degraded),
    /// onboarding, or minting (locked). Reserved-by-a-live-entry or orphaned vouchers contribute
    /// nowhere. The single inclusion rule shared by the balance and the voucher count/list, so a
    /// voucher absent from the balance is absent from both. Mirrors
    /// `CoinageBalanceService.calculateBalance`.
    public var isBalanceCounted: Bool {
        isSelectable || isOnboarding || isMinting
    }
}

extension TrackedVoucher: Operation_iOS.Identifiable {
    public var identifier: String {
        voucher.identifier
    }
}
