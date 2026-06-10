import BigInt
import Foundation
import SubstrateSdk

/// Plans how to fulfill an external payment from available coins and vouchers.
///
/// Algorithm (greedy, largest-value-first):
/// 1. Fetch vouchers, evaluate readiness, partition into ready/waiting
/// 2. If ready vouchers cover the amount → `.ready`
/// 3. If total vouchers (ready + waiting) cover it → `.needsReschedule`
/// 4. Calculate deficit, check available coins
/// 5. If coins cover deficit → `.loadCoins`
/// 6. If total coins cover deficit → `.needsReschedule`
/// 7. Otherwise → `.notEnoughBalance`
struct ExternalPaymentPlanner: ExternalPaymentPlanning {
    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol

    private let rescheduleDelay: TimeInterval = 6

    init(
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol
    ) {
        self.coinService = coinService
        self.voucherService = voucherService
    }

    func plan(
        amount: Balance,
        context: DenominationBreakdownContext
    ) async throws -> ExternalPaymentPreview {
        let vouchers = try await voucherService.fetchAll().filter { $0.localState == .available }

        let readyVouchers = vouchers.filter(\.remoteState.isInRecycler)
        let waitingVouchers = vouchers.filter { !$0.remoteState.isInRecycler }

        // Try ready vouchers first
        let readyTotal = totalValue(of: readyVouchers, context: context)
        if readyTotal >= amount {
            let selected = selectVouchers(from: readyVouchers, target: amount, context: context)
            let nonDegraded = nonDegradedAmount(from: selected, context: context)
            let selection = ExternalPaymentPreview.Selection(
                vouchers: selected,
                coins: [],
                fullAmount: amount,
                nonDegradedAmount: nonDegraded
            )
            return .ready(selection)
        }

        let fullPrivacyNonDegraded = nonDegradedAmount(from: readyVouchers, context: context)

        // Check if total vouchers (ready + waiting) would be enough
        let totalVoucherValue = readyTotal + totalValue(of: waitingVouchers, context: context)
        if totalVoucherValue >= amount {
            let selection = ExternalPaymentPreview.Selection(
                vouchers: readyVouchers,
                coins: [],
                fullAmount: amount,
                nonDegradedAmount: fullPrivacyNonDegraded
            )
            return .needsReschedule(
                after: Date(timeIntervalSinceNow: rescheduleDelay),
                selection
            )
        }

        // Calculate deficit and check coins
        let deficit = amount - totalVoucherValue

        let allCoins = try await coinService.fetchAllCoins()
        let spendableCoins = allCoins.filter { $0.state == .available }
        let nonSpentCoins = allCoins.filter(\.state.isAvailableOrRecycling)
        let spendableTotal = totalValue(of: spendableCoins, context: context)

        if spendableTotal >= deficit {
            let selectedCoins = selectCoins(from: spendableCoins, target: deficit, context: context)
            let selection = ExternalPaymentPreview.Selection(
                vouchers: readyVouchers,
                coins: selectedCoins,
                fullAmount: amount,
                nonDegradedAmount: fullPrivacyNonDegraded
            )
            return .loadCoins(selection)
        }

        // Check if non-spent coins (available + recycling + pendingTransfer) would cover it
        let nonSpentTotal = totalValue(of: nonSpentCoins, context: context)
        if nonSpentTotal >= deficit {
            let selection = ExternalPaymentPreview.Selection(
                vouchers: readyVouchers,
                coins: nonSpentCoins,
                fullAmount: amount,
                nonDegradedAmount: fullPrivacyNonDegraded
            )
            return .needsReschedule(
                after: Date(timeIntervalSinceNow: rescheduleDelay),
                selection
            )
        }

        return .notEnoughBalance
    }
}

// MARK: - Selection Helpers

private extension ExternalPaymentPlanner {
    func totalValue(of vouchers: [Voucher], context: DenominationBreakdownContext) -> Balance {
        vouchers.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.exponent) }
    }

    func totalValue(of coins: [Coin], context: DenominationBreakdownContext) -> Balance {
        coins.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.exponent) }
    }

    func nonDegradedAmount(from vouchers: [Voucher], context: DenominationBreakdownContext) -> BigUInt {
        vouchers
            .filter { $0.effectivePrivacy() == .full }
            .reduce(BigUInt.zero) { $0 + context.valueInPlanks(for: $1.exponent) }
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
