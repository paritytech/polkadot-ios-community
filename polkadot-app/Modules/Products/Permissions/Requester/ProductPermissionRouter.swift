import Products
import UIKit
import UIKitExt

/// Presents ``ProductPermissionPrompt`` as a bottom sheet above the host
/// product view controller. Follows the same pattern as
/// ``ProductsSigningRouter``: the presenter view is injected lazily after the
/// module is created.
@MainActor
final class ProductPermissionRouter: ProductPermissionRouting {
    private weak var presentationView: ControllerBackedProtocol?

    nonisolated init() {}

    func setPresentationView(_ view: ControllerBackedProtocol) {
        presentationView = view
    }

    func showPrompt(context: ProductPermissionContext) {
        let promptView = ProductPermissionPromptViewFactory.createView(context: context)

        presentationView?.controller.present(promptView.controller, animated: true)
    }
}
