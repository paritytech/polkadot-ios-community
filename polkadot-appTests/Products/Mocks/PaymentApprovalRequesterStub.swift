import Products
import SubstrateSdk

struct PaymentApprovalRequesterStub: PaymentApprovalRequesting {
    let decision: PaymentApprovalDecision

    func requestApproval(
        productId _: String,
        amount _: Balance,
        destination _: AccountId
    ) async -> PaymentApprovalDecision {
        decision
    }
}
