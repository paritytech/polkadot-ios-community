import Foundation
import SubstrateSdk

/// Wraps a balance amount in planks together with the denomination breakdown
/// context needed to interpret it as a human-readable decimal.
public struct CoinageBalance: Equatable {
    public let planks: Balance
    public let context: DenominationBreakdownContext

    public init(planks: Balance, context: DenominationBreakdownContext) {
        self.planks = planks
        self.context = context
    }

    /// Balance in planks — the smallest indivisible on-chain unit.
    public func balanceInPlanks() -> Balance {
        planks
    }

    /// Balance in decimal currency units (e.g. pUSD), derived from planks
    /// using the asset precision encoded in the breakdown context.
    public func balanceInDecimal() -> Decimal {
        Decimal.fromSubstrateAmount(planks, precision: context.precision) ?? 0
    }
}
