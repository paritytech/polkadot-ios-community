import Foundation

protocol ConfirmationGateRuleProtocol: Sendable {
    func requiresAuthentication(amount: Decimal, totalCash: Decimal?) -> Bool
}

/// Decides whether a payment needs device authentication. Unknown total fails closed.
struct ConfirmationGateRule: ConfirmationGateRuleProtocol {
    let absoluteLimit: Decimal
    let shareOfTotal: Decimal

    init(
        absoluteLimit: Decimal = AppConfig.ConfirmationLimit.absolute,
        shareOfTotal: Decimal = AppConfig.ConfirmationLimit.shareOfTotal
    ) {
        self.absoluteLimit = absoluteLimit
        self.shareOfTotal = max(min(shareOfTotal, 1), 0)
    }

    func requiresAuthentication(amount: Decimal, totalCash: Decimal?) -> Bool {
        guard let totalCash else { return true }

        return amount > confirmationLimit(totalCash: totalCash)
    }
}

private extension ConfirmationGateRule {
    /// The smaller of the absolute limit and the share of the total Cash.
    func confirmationLimit(totalCash: Decimal) -> Decimal {
        min(absoluteLimit, totalCash * shareOfTotal)
    }
}
