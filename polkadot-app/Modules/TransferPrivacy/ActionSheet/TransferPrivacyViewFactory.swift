import UIKit
import PolkadotUI
import UIKit_iOS

@MainActor
enum TransferPrivacyViewFactory {
    static func createGainingPrivacyConfirmation(
        amount: String,
        onSendAnyway: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> UIViewController {
        let wireframe = TransferPrivacyWireframe()
        let presenter = TransferPrivacyPresenter(
            model: TransferPrivacyModel(amount: amount),
            wireframe: wireframe,
            onSendAnyway: onSendAnyway,
            onCancel: onCancel
        )
        let view = TransferPrivacyViewController(presenter: presenter)
        presenter.view = view

        let nav = ModalDelegatingNavigationController(rootViewController: view)
        BottomSheetViewFacade.setupBottomSheet(from: nav)

        return nav
    }
}

/// The sheet presentation controller looks for ``ModalPresenterDelegate`` on the presented controller
/// only, so a navigation wrapper must forward the dismissal hooks to its root, or a backdrop tap and
/// a swipe would dismiss the sheet without any callback.
private final class ModalDelegatingNavigationController: UINavigationController, ModalPresenterDelegate {
    private var delegateRoot: ModalPresenterDelegate? {
        viewControllers.first as? ModalPresenterDelegate
    }

    func presenterShouldHide(_ presenter: ModalPresenterProtocol) -> Bool {
        delegateRoot?.presenterShouldHide(presenter) ?? true
    }

    func presenterDidHide(_ presenter: ModalPresenterProtocol) {
        delegateRoot?.presenterDidHide(presenter)
    }
}
