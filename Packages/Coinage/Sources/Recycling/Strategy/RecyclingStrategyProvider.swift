import Foundation
import SubstrateSdk
import BigInt

protocol RecyclingStrategyProviding {
    func coinStrategy(for type: RecyclingStrategyType) async throws -> CoinRecyclingStrategyProtocol

    func voucherStrategy(for type: RecyclingStrategyType) -> CoinRecyclingStrategyProtocol
}

/// Assembles the decorated strategy for a given preset. Plain composition — the chain is rebuilt per
/// call because `quotaExhausted` moves. The voucher arm needs no quota read, so it is offered bare.
public struct RecyclingStrategyProvider: RecyclingStrategyProviding {
    private let quotaTracker: any UnloadQuotaTracking
    private let forcedRecyclingAge: Int16
    private let quotaReserve: BigRational

    /// `quotaReserve` holds a fraction of the period allowance back for forced recycling and real
    /// payments; the valve engages once remaining crosses it.
    public init(
        quotaTracker: any UnloadQuotaTracking,
        forcedRecyclingAge: Int16 = CoinageConstants.recycleAtAge,
        quotaReserve: BigRational = .percent(of: 20)
    ) {
        self.quotaTracker = quotaTracker
        self.forcedRecyclingAge = forcedRecyclingAge
        self.quotaReserve = quotaReserve
    }

    /// The full decorated policy: chain-limits wraps quota-limits wraps the parametric policy.
    public func coinStrategy(for type: RecyclingStrategyType) async throws -> CoinRecyclingStrategyProtocol {
        let quota = try await quotaTracker.remainingQuota()
        let threshold = quotaReserve.mul(value: BigUInt(max(0, quota.limit)))
        let quotaExhausted = BigUInt(max(0, quota.remaining)) <= threshold

        return EnsureChainLimitsStrategy(
            inner: EnsureQuotaLimitsStrategy(
                inner: ParametricRecyclingStrategy(params: type.params(forcedRecyclingAge: forcedRecyclingAge)),
                quotaExhausted: quotaExhausted
            ),
            forcedRecyclingAge: forcedRecyclingAge
        )
    }

    /// Voucher usability only: both decorators delegate it untouched, so a bare policy suffices and
    /// no quota read happens on the balance path.
    public func voucherStrategy(for type: RecyclingStrategyType) -> CoinRecyclingStrategyProtocol {
        ParametricRecyclingStrategy(params: type.params(forcedRecyclingAge: forcedRecyclingAge))
    }
}
