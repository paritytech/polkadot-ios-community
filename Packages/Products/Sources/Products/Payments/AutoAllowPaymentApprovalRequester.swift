import Foundation
import SubstrateSdk

/// Approves payments without a prompt for an allowlisted set of products. Each auto-allowed payment
/// still goes through `confirmAutoApproval`, which decides by amount whether the device owner must
/// authenticate. Wraps the real requester for everything else. Same shape and rationale as
/// ``AutoAllowProductPermissionRequester``.
public struct AutoAllowPaymentApprovalRequester: PaymentApprovalRequesting {
    private let allowedLabels: Set<String>
    private let confirmAutoApproval: @Sendable (Balance) async -> Bool
    private let wrapped: PaymentApprovalRequesting

    public init(
        allowedLabels: Set<String>,
        confirmAutoApproval: @escaping @Sendable (Balance) async -> Bool,
        wrapped: PaymentApprovalRequesting
    ) {
        self.allowedLabels = allowedLabels
        self.confirmAutoApproval = confirmAutoApproval
        self.wrapped = wrapped
    }

    public func requestApproval(
        productId: String,
        amount: Balance,
        destination: AccountId
    ) async -> PaymentApprovalDecision {
        guard !isAutoAllowed(productId: productId) else {
            return await confirmAutoApproval(amount) ? .approved : .rejected
        }

        return await wrapped.requestApproval(
            productId: productId,
            amount: amount,
            destination: destination
        )
    }
}

private extension AutoAllowPaymentApprovalRequester {
    /// Matches the label only, dropping the root: the root is the chain TLD and
    /// differs per network, and resolving it here would put a network call in
    /// front of an auto-allow.
    func isAutoAllowed(productId: String) -> Bool {
        guard let name = ProductHost.name(fromDotDomain: productId) else { return false }

        return allowedLabels.contains(name)
    }
}
