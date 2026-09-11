import Foundation
import Products
import SubstrateSdk

/// Presents the payment request sheet and suspends until the user decides.
final class PaymentApprovalRequester: PaymentApprovalRequesting, @unchecked Sendable {
    private let router: ProductsRouting

    init(router: ProductsRouting) {
        self.router = router
    }

    func requestApproval(
        productId: String,
        amount: Balance,
        destination: AccountId
    ) async -> PaymentApprovalDecision {
        let context = PaymentRequestContext(
            productId: productId,
            amountInPlanks: amount,
            destination: destination
        )

        return await withCheckedContinuation { continuation in
            context.setContinuation(continuation)
            Task { @MainActor [router] in
                router.showPaymentRequest(context: context)
            }
        }
    }
}
