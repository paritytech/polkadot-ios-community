import Foundation
import Products

enum PaymentApprovalRequesterFactory {
    static func create(
        router: ProductsRouting,
        fundingProvider: FundingDomainProviding,
        paymentsSupport: PaymentsSupport?
    ) -> PaymentApprovalRequesting {
        let gate = PaymentConfirmationGate(
            coinageService: paymentsSupport?.coinageService,
            chainAssetProvider: { await PaymentRequestViewFactory.mainChainAsset() },
            rule: ConfirmationGateRule()
        )

        return AutoAllowPaymentApprovalRequester(
            allowedLabels: ProductAutoAllowList.labels(fundingProvider: fundingProvider),
            confirmAutoApproval: { amount in
                guard await gate.requiresAuthentication(amount: amount) else { return true }
                return await authorizeDeviceOwner()
            },
            wrapped: PaymentApprovalRequester(router: router, gate: gate)
        )
    }
}

private extension PaymentApprovalRequesterFactory {
    @MainActor
    static func authorizeDeviceOwner() async -> Bool {
        await withCheckedContinuation { continuation in
            let authorizer = DeviceOwnerAuthorizer()
            authorizer.authorize(animated: true, retriable: false) { isAuthorized in
                continuation.resume(returning: isAuthorized)
            }
        }
    }
}
