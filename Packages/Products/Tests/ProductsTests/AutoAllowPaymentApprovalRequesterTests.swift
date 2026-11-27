import Foundation
import Testing
import SubstrateSdk
@testable import Products

@Suite("AutoAllowPaymentApprovalRequester Tests")
struct AutoAllowPaymentApprovalRequesterTests {
    private let allowedLabels = Set(["getcash"])
    private let destination = Data(repeating: 7, count: 32)

    private func makeSUT(
        wrappedDecision: PaymentApprovalDecision = .rejected,
        confirmResult: Bool = true
    ) -> (
        requester: AutoAllowPaymentApprovalRequester,
        wrapped: MockPaymentApprovalRequester,
        confirmations: MockAutoApprovalConfirmation
    ) {
        let wrapped = MockPaymentApprovalRequester()
        wrapped.decision = wrappedDecision
        let confirmations = MockAutoApprovalConfirmation()
        let requester = AutoAllowPaymentApprovalRequester(
            allowedLabels: allowedLabels,
            confirmAutoApproval: { amount in
                await confirmations.record(amount)
                return confirmResult
            },
            wrapped: wrapped
        )
        return (requester, wrapped, confirmations)
    }

    @Test("approves allowlisted product when confirmation passes, without asking")
    func approvesAllowlistedWhenConfirmed() async {
        let (requester, wrapped, confirmations) = makeSUT(confirmResult: true)

        let decision = await requester.requestApproval(
            productId: "getcash.dot",
            amount: 100,
            destination: destination
        )
        let confirmedAmounts = await confirmations.amounts

        #expect(decision == .approved)
        #expect(wrapped.calls.isEmpty)
        #expect(confirmedAmounts == [100])
    }

    @Test("rejects allowlisted product when confirmation fails")
    func rejectsAllowlistedWhenNotConfirmed() async {
        let (requester, wrapped, _) = makeSUT(confirmResult: false)

        let decision = await requester.requestApproval(
            productId: "getcash.dot",
            amount: 100,
            destination: destination
        )

        #expect(decision == .rejected)
        #expect(wrapped.calls.isEmpty)
    }

    @Test("delegates non-allowlisted product to wrapped without confirming")
    func delegatesNonAllowlisted() async {
        let (requester, wrapped, confirmations) = makeSUT(wrappedDecision: .rejected)

        let decision = await requester.requestApproval(
            productId: "other.dot",
            amount: 100,
            destination: destination
        )
        let confirmedAmounts = await confirmations.amounts

        #expect(decision == .rejected)
        #expect(wrapped.calls.count == 1)
        #expect(wrapped.calls.first?.productId == "other.dot")
        #expect(confirmedAmounts.isEmpty)
    }

    @Test("delegates bare productId without root", arguments: ["getcash", "getcash..dot"])
    func delegatesMalformedProductId(productId: String) async {
        let (requester, wrapped, confirmations) = makeSUT(wrappedDecision: .approved)

        let decision = await requester.requestApproval(
            productId: productId,
            amount: 100,
            destination: destination
        )
        let confirmedAmounts = await confirmations.amounts

        #expect(decision == .approved)
        #expect(wrapped.calls.count == 1)
        #expect(confirmedAmounts.isEmpty)
    }
}
