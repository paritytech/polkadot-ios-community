import UIKit

final class SSOSigningRouter: SigningRouting {
    @MainActor
    func presentSigning(with context: PolkadotSigningContextProtocol) -> UIViewController? {
        guard let signingView = PolkadotSigningViewFactory.createView(
            signingContext: context
        ) else {
            return nil
        }

        let controller = signingView.controller

        guard let window = UIWindow.keyWindow,
              let presenter = window.topmostViewController else {
            return nil
        }

        presenter.present(controller, animated: true)

        return controller
    }
}
