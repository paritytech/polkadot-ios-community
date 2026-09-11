import BigInt
import Foundation
import SubstrateSdk

/// Plans how to fulfill an external payment from what is spendable on-chain right now.
public protocol ExternalPaymentPlanning {
    /// `mustInclude` vouchers are taken first (a re-entered onboarding forces its freshly recycled
    /// vouchers in), then the rest greedily.
    func plan(
        amount: Balance,
        context: DenominationBreakdownContext,
        mustInclude: [Voucher]
    ) async throws -> ExternalPaymentPreview
}
