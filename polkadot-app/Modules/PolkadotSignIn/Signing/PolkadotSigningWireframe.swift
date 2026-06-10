import UIKit

final class PolkadotSigningWireframe: PolkadotSigningWireframeProtocol {
    func hide(view: PolkadotSigningViewProtocol?) {
        view?.controller.dismiss(animated: true)
    }

    func showViewDetails(
        with text: String,
        isTransaction: Bool,
        view: PolkadotSigningViewProtocol?
    ) {
        guard let detailsView = PolkadotSigningDetailsViewFactory.createView(
            detailsText: text,
            isTransaction: isTransaction
        ) else {
            return
        }
        let nav = AppNavigationController(rootViewController: detailsView.controller)
        view?.controller.present(nav, animated: true)
    }
}
