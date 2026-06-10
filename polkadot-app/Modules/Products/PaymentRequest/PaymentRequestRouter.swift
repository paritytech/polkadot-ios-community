import UIKit
import UIKitExt

@MainActor
protocol PaymentRequestRouting: AnyObject {
    func showPaymentRequest(context: PaymentRequestContext)
}

@MainActor
final class PaymentRequestRouter: PaymentRequestRouting {
    private weak var presentationView: ControllerBackedProtocol?

    nonisolated init() {}

    func setPresentationView(_ view: ControllerBackedProtocol) {
        presentationView = view
    }

    func showPaymentRequest(context: PaymentRequestContext) {
        guard let view = PaymentRequestViewFactory.createView(context: context) else {
            context.deliverRejected()
            return
        }

        presentationView?.controller.present(view.controller, animated: true)
    }
}
