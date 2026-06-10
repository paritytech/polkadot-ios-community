import Products
import UIKit
import UIKitExt

/// Presents the resource allocation approval bottom sheet above the host
/// product view controller. Follows the same pattern as
/// ``ProductPermissionRouter``.
@MainActor
final class AllowancePromptRouter: AllowancePromptRouting {
    private weak var presentationView: ControllerBackedProtocol?

    nonisolated init() {}

    func setPresentationView(_ view: ControllerBackedProtocol) {
        presentationView = view
    }

    func showAllowancePrompt(context: AllowancePromptContext) {
        let promptView = AllowancePromptViewFactory.createView(context: context)

        let presentationController = presentationView?.controller.presentedViewController ?? presentationView?
            .controller
        presentationController?.present(promptView.controller, animated: true)
    }
}
