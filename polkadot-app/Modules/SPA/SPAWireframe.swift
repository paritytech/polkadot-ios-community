import UIKit
import Products
import UIKitExt

final class SPAWireframe: SPAWireframeProtocol, ChatNavigating {
    private let flowState: SPAFlowState

    init(flowState: SPAFlowState) {
        self.flowState = flowState
    }

    func openChat(
        from view: ControllerBackedProtocol?,
        chatId: Chat.Id
    ) {
        if let presentingController = view?.controller.navigationController?.presentingViewController {
            presentingController.dismiss(animated: true)
        } else {
            view?.controller.navigationController?.popToRootViewController(animated: true)
        }

        navigateToChat(with: chatId, force: false)
    }

    func showProductSPA(from view: ControllerBackedProtocol?, productHost: ProductHost) {
        let configuration = SPAConfiguration.product(host: productHost)

        guard
            let spaView = SPAViewFactory.createView(
                configuration: configuration,
                flowState: flowState
            ) else {
            return
        }

        let navigationController = SPAViewFactory.makeCardNavigationController(for: spaView)
        navigationController.modalPresentationStyle = .fullScreen
        view?.controller.present(navigationController, animated: true)
    }

    func showMoreActions(
        from view: ControllerBackedProtocol?,
        actions: [SPAMoreAction],
        closeTitle: String
    ) {
        guard let view else { return }

        let sheet = SPAMoreActionsViewFactory.createView(
            actions: actions,
            closeTitle: closeTitle
        )
        view.controller.present(sheet.controller, animated: true)
    }

    func shareURL(_ url: URL, from view: ControllerBackedProtocol?) {
        guard let view else { return }

        let sheet = ShareViewFactory.createView(items: [.url(url)], host: view)
        view.controller.present(sheet.controller, animated: true)
    }
}
