import Foundation
import Products
import SubstrateSdk

/// Presents the payment request sheet and suspends until the user decides.
final class PaymentApprovalRequester: PaymentApprovalRequesting, @unchecked Sendable {
    private let router: ProductsRouting
    private let gate: PaymentConfirmationGating

    init(router: ProductsRouting, gate: PaymentConfirmationGating) {
        self.router = router
        self.gate = gate
    }

    func requestApproval(
        productId: String,
        amount: Balance,
        destination: AccountId
    ) async -> PaymentApprovalDecision {
        let requiresAuthentication = await gate.requiresAuthentication(amount: amount)

        return await withCheckedContinuation { continuation in
            Task { @MainActor [router] in
                let context = PaymentRequestContext(
                    productId: productId,
                    amountInPlanks: amount,
                    destination: destination,
                    requiresAuthentication: requiresAuthentication
                )
                context.setContinuation(continuation)
                router.showPaymentRequest(context: context)
            }
        }
    }
}
