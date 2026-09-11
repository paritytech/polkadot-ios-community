import BigInt
import Foundation
import SubstrateSdk

/// Plans how to fulfill an external payment from the strategy buckets of ``SpendableAssetsProviding``.
///
/// Algorithm (greedy, largest-value-first):
/// 1. No verdicts yet → `.needsReschedule` (never fall back to raw structural readiness)
/// 2. Spendable vouchers cover the amount → `.ready`
/// 3. Spendable + gaining-privacy + pending vouchers cover it → `.needsReschedule` (at the earliest
///    gaining `readyAt`, not before the base delay)
/// 4. Deficit against all vouchers; spendable coins cover it → `.loadCoins`
/// 5. Spendable + gaining + pending coins cover it → `.needsReschedule`
/// 6. Otherwise → `.notEnoughBalance`
struct ExternalPaymentPlanner: ExternalPaymentPlanning {
    private let spendableAssets: any SpendableAssetsProviding
    private let rescheduleDelay: TimeInterval

    init(spendableAssets: any SpendableAssetsProviding, rescheduleDelay: TimeInterval = 6) {
        self.spendableAssets = spendableAssets
        self.rescheduleDelay = rescheduleDelay
    }

    func plan(
        amount: Balance,
        context: DenominationBreakdownContext,
        scope: SpendScope
    ) async throws -> ExternalPaymentPreview {
        guard let assets = try await spendableAssets.spendableAssets(scope: scope) else {
            return .needsReschedule(
                after: Date(timeIntervalSinceNow: rescheduleDelay),
                selection(vouchers: [], coins: [], amount: amount, scope: scope)
            )
        }

        let spendableVoucherTotal = totalValue(of: assets.spendableVouchers, context: context)
        if spendableVoucherTotal >= amount {
            let selected = selectVouchers(from: assets.spendableVouchers, target: amount, context: context)
            return .ready(selection(vouchers: selected, coins: [], amount: amount, scope: scope))
        }

        let waitingVouchers = assets.gainingPrivacyVouchers + assets.pendingVouchers
        let totalVoucherValue = spendableVoucherTotal + totalValue(of: waitingVouchers, context: context)
        if totalVoucherValue >= amount {
            return .needsReschedule(
                after: rescheduleDate(for: assets.gainingPrivacyVouchers),
                selection(vouchers: assets.spendableVouchers, coins: [], amount: amount, scope: scope)
            )
        }

        let deficit = amount - totalVoucherValue
        let spendableCoinTotal = totalValue(of: assets.spendableCoins, context: context)
        if spendableCoinTotal >= deficit {
            let selectedCoins = selectCoins(from: assets.spendableCoins, target: deficit, context: context)
            return .loadCoins(
                selection(vouchers: assets.spendableVouchers, coins: selectedCoins, amount: amount, scope: scope)
            )
        }

        // Gaining coins are recycled into vouchers by the recycling service on its own; pending
        // coins are minting or awaiting mandatory recycling. Wait for them rather than failing.
        let waitingCoins = assets.gainingPrivacyCoins + assets.pendingCoins
        if spendableCoinTotal + totalValue(of: waitingCoins, context: context) >= deficit {
            return .needsReschedule(
                after: Date(timeIntervalSinceNow: rescheduleDelay),
                selection(
                    vouchers: assets.spendableVouchers,
                    coins: assets.spendableCoins + waitingCoins,
                    amount: amount,
                    scope: scope
                )
            )
        }

        return .notEnoughBalance
    }
}

// MARK: - Selection Helpers

private extension ExternalPaymentPlanner {
    func selection(
        vouchers: [Voucher],
        coins: [Coin],
        amount: Balance,
        scope: SpendScope
    ) -> ExternalPaymentPreview.Selection {
        ExternalPaymentPreview.Selection(vouchers: vouchers, coins: coins, fullAmount: amount, scope: scope)
    }

    /// Never earlier than the base delay; otherwise the earliest moment a gaining voucher matures.
    func rescheduleDate(for gainingVouchers: [Voucher]) -> Date {
        let base = Date(timeIntervalSinceNow: rescheduleDelay)
        guard let earliest = gainingVouchers.map(\.readyAt).min() else { return base }
        return max(base, earliest)
    }

    func totalValue(of vouchers: [Voucher], context: DenominationBreakdownContext) -> Balance {
        vouchers.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.exponent) }
    }

    func totalValue(of coins: [Coin], context: DenominationBreakdownContext) -> Balance {
        coins.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.exponent) }
    }

    /// Greedy voucher selection: sort by value descending, accumulate until >= target.
    func selectVouchers(
        from vouchers: [Voucher],
        target: Balance,
        context: DenominationBreakdownContext
    ) -> [Voucher] {
        let sorted = vouchers
            .sorted { context.valueInPlanks(for: $0.exponent) > context.valueInPlanks(for: $1.exponent) }

        var selected: [Voucher] = []
        var accumulated = Balance(0)

        for voucher in sorted {
            if accumulated >= target { break }
            selected.append(voucher)
            accumulated += context.valueInPlanks(for: voucher.exponent)
        }

        return selected
    }

    /// Greedy coin selection: sort by value descending, accumulate until >= target.
    func selectCoins(
        from coins: [Coin],
        target: Balance,
        context: DenominationBreakdownContext
    ) -> [Coin] {
        let sorted = coins.sorted { context.valueInPlanks(for: $0.exponent) > context.valueInPlanks(for: $1.exponent) }

        var selected: [Coin] = []
        var accumulated = Balance(0)

        for coin in sorted {
            if accumulated >= target { break }
            selected.append(coin)
            accumulated += context.valueInPlanks(for: coin.exponent)
        }

        return selected
    }
}
