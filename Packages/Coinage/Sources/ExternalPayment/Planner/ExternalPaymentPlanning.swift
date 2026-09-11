import BigInt
import Foundation
import SubstrateSdk

/// Plans how to fulfill an external payment from the assets a ``SpendScope`` may draw on.
public protocol ExternalPaymentPlanning {
    func plan(
        amount: Balance,
        context: DenominationBreakdownContext,
        scope: SpendScope
    ) async throws -> ExternalPaymentPreview
}
