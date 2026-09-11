import BigInt
import Foundation
import SubstrateSdk

/// Plans an external payment from structural on-chain spendability: free vouchers in a recycler and
/// free, on-chain, age-valid coins. Recycling verdicts and ring usability are deliberately ignored —
/// the user consented to a privacy-leaking spend before the payment was registered.
///
/// Algorithm (greedy, largest-value-first):
/// 1. `mustInclude` first, then spendable vouchers until they cover the amount → `.ready`
/// 2. Deficit against all spendable vouchers; spendable coins cover it → `.loadCoins`
/// 3. Otherwise → `.notEnoughBalance`
struct ExternalPaymentPlanner: ExternalPaymentPlanning {
    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol

    init(coinService: CoinServiceProtocol, voucherService: VoucherServiceProtocol) {
        self.coinService = coinService
        self.voucherService = voucherService
    }

    func plan(
        amount: Balance,
        context: DenominationBreakdownContext,
        mustInclude: [Voucher]
    ) async throws -> ExternalPaymentPreview {
        let forced = Set(mustInclude.map(\.derivationIndex))
        let spendableVouchers = try await voucherService.fetchAllTracked()
            .filter { $0.isSelectable && !forced.contains($0.voucher.derivationIndex) }
            .map(\.voucher)

        let voucherTotal = totalValue(of: mustInclude + spendableVouchers, context: context)
        if voucherTotal >= amount {
            let selected = mustInclude + select(from: spendableVouchers, target: amount, context: context) {
                totalValue(of: mustInclude, context: context)
            }
            return .ready(Selection(vouchers: selected, coins: [], fullAmount: amount))
        }

        let deficit = amount - voucherTotal
        let spendableCoins = try await coinService.fetchAllTrackedCoins()
            .filter(\.isSelectable)
            .map(\.coin)

        guard totalValue(of: spendableCoins, context: context) >= deficit else {
            return .notEnoughBalance
        }

        let coins = select(from: spendableCoins, target: deficit, context: context) { 0 }
        return .loadCoins(Selection(vouchers: mustInclude + spendableVouchers, coins: coins, fullAmount: amount))
    }
}

// MARK: - Selection Helpers

private extension ExternalPaymentPlanner {
    typealias Selection = ExternalPaymentPreview.Selection

    func totalValue(of vouchers: [Voucher], context: DenominationBreakdownContext) -> Balance {
        vouchers.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.exponent) }
    }

    func totalValue(of coins: [Coin], context: DenominationBreakdownContext) -> Balance {
        coins.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.exponent) }
    }

    /// Greedy largest-first accumulation until `target` is reached, starting from `seed()`.
    func select<Asset: DenominatedAsset>(
        from assets: [Asset],
        target: Balance,
        context: DenominationBreakdownContext,
        seed: () -> Balance
    ) -> [Asset] {
        let sorted = assets.sorted {
            context.valueInPlanks(for: $0.exponent) > context.valueInPlanks(for: $1.exponent)
        }

        var selected: [Asset] = []
        var accumulated = seed()

        for asset in sorted {
            if accumulated >= target { break }
            selected.append(asset)
            accumulated += context.valueInPlanks(for: asset.exponent)
        }

        return selected
    }
}

/// The two asset kinds the greedy picker ranks by value.
private protocol DenominatedAsset {
    var exponent: Int16 { get }
}

extension Coin: DenominatedAsset {}
extension Voucher: DenominatedAsset {}
