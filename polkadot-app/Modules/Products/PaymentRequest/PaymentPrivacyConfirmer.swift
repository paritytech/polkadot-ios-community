import Foundation
import Products
import SubstrateSdk
import UIKit
import UIKitExt

/// Presents the same gaining-privacy sheet transfers use, on the products presentation anchor.
/// Never allowlisted: losing earned privacy is the user's call for every product.
final class PaymentPrivacyConfirmer: PaymentPrivacyConfirming, @unchecked Sendable {
    private let router: ProductsRouting

    init(router: ProductsRouting) {
        self.router = router
    }

    func confirmGainingPrivacySpend(amount: Balance) async -> Bool {
        let decision = await OneShotDecision()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { @MainActor [router] in
                    decision.arm(continuation)
                    present(amount: amount, on: router, decision: decision)
                }
            }
        } onCancel: {
            Task { @MainActor in decision.resolve(false) }
        }
    }
}

private extension PaymentPrivacyConfirmer {
    @MainActor
    func present(amount: Balance, on router: ProductsRouting, decision: OneShotDecision) {
        guard let chainAsset = PaymentRequestViewFactory.mainChainAsset() else {
            decision.resolve(false)
            return
        }

        let sheet = TransferPrivacyViewFactory.createGainingPrivacyConfirmation(
            amount: PaymentRequestViewFactory.formatAmount(amount, chainAsset: chainAsset),
            onSendAnyway: { decision.resolve(true) },
            onCancel: { decision.resolve(false) }
        )

        if !router.present(view: PresentedController(controller: sheet)) {
            decision.resolve(false)
        }
    }

    /// Main-actor owner of the pending continuation: the sheet's buttons, its dismissal, a failed
    /// presentation and task cancellation may all answer, and only the first answer counts.
    @MainActor
    final class OneShotDecision {
        private var continuation: CheckedContinuation<Bool, Never>?
        private var pending: Bool?

        func arm(_ continuation: CheckedContinuation<Bool, Never>) {
            if let pending {
                continuation.resume(returning: pending)
            } else {
                self.continuation = continuation
            }
        }

        func resolve(_ decision: Bool) {
            guard pending == nil else { return }
            pending = decision
            continuation?.resume(returning: decision)
            continuation = nil
        }
    }

    final class PresentedController: ControllerBackedProtocol {
        let controller: UIViewController

        init(controller: UIViewController) {
            self.controller = controller
        }

        var isSetup: Bool { controller.isViewLoaded }
    }
}
