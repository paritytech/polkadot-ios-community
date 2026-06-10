import UIKit
import UIKitExt

@MainActor
final class ProductsSigningRouter: SigningRouting {
    private weak var presentationView: ControllerBackedProtocol?

    nonisolated init() {}

    func setPresentationView(_ view: ControllerBackedProtocol) {
        presentationView = view
    }

    func presentSigning(with context: PolkadotSigningContextProtocol) -> UIViewController? {
        guard let signingView = PolkadotSigningViewFactory.createView(
            signingContext: context
        ) else {
            return nil
        }

        let controller = signingView.controller
        presentationView?.controller.present(controller, animated: true)
        return controller
    }
}
