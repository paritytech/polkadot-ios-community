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
        await withCheckedContinuation { continuation in
            Task { @MainActor [router] in
                let gate = OneShotDecision(continuation)

                guard let chainAsset = PaymentRequestViewFactory.mainChainAsset() else {
                    gate.resolve(false)
                    return
                }

                let sheet = TransferPrivacyViewFactory.createGainingPrivacyConfirmation(
                    amount: PaymentRequestViewFactory.formatAmount(amount, chainAsset: chainAsset),
                    onSendAnyway: { gate.resolve(true) },
                    onCancel: { gate.resolve(false) }
                )

                if !router.present(view: PresentedController(controller: sheet)) {
                    gate.resolve(false)
                }
            }
        }
    }
}

private extension PaymentPrivacyConfirmer {
    /// The sheet may report both a choice and a dismissal; only the first answer counts.
    final class OneShotDecision {
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func resolve(_ decision: Bool) {
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
