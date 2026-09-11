import Foundation

/// The wallet bucketed by what a spend under a given ``SpendScope`` may draw on. Built from the
/// recycling verdicts and voucher usability, never from raw structural readiness.
public struct SpendableAssets: Sendable {
    /// Coins and vouchers the scope may spend now.
    public let spendableCoins: [Coin]
    public let spendableVouchers: [Voucher]
    /// Held back by the privacy strategy; become usable on their own (vouchers carry `readyAt`).
    public let gainingPrivacyCoins: [Coin]
    public let gainingPrivacyVouchers: [Voucher]
    /// Minting, onboarding, or awaiting mandatory recycling.
    public let pendingCoins: [Coin]
    public let pendingVouchers: [Voucher]

    public init(
        spendableCoins: [Coin],
        spendableVouchers: [Voucher],
        gainingPrivacyCoins: [Coin],
        gainingPrivacyVouchers: [Voucher],
        pendingCoins: [Coin],
        pendingVouchers: [Voucher]
    ) {
        self.spendableCoins = spendableCoins
        self.spendableVouchers = spendableVouchers
        self.gainingPrivacyCoins = gainingPrivacyCoins
        self.gainingPrivacyVouchers = gainingPrivacyVouchers
        self.pendingCoins = pendingCoins
        self.pendingVouchers = pendingVouchers
    }
}

/// The strategy seam the external payment planner reads.
public protocol SpendableAssetsProviding: Sendable {
    /// `nil` until the recycling evaluator has produced its first verdicts; callers reschedule on nil.
    func spendableAssets(scope: SpendScope) async throws -> SpendableAssets?
}

/// One-method read of the evaluator's latest verdicts. `CoinageService` conforms; the provider holds
/// it weakly because the service owns the provider transitively.
public protocol RecyclingVerdictsReading: AnyObject, Sendable {
    func currentRecyclingVerdicts() async -> RecyclingVerdicts?
}
