import UIKit
import PolkadotUI
import UIKit_iOS

enum TransferPrivacyViewFactory {
    static func createView(
        from model: TransferPrivacyModel,
        onSendDegraded: @escaping () -> Void,
        onSendNonDegraded: @escaping () -> Void,
        onCancel _: (() -> Void)? = nil
    ) -> UIViewController {
        let wireframe = TransferPrivacyWireframe()
        let presenter = TransferPrivacyPresenter(
            model: model,
            wireframe: wireframe,
            onMainTapped: onSendNonDegraded,
            onSecondaryTapped: onSendDegraded
        )
        let view = TransferPrivacyViewController(presenter: presenter)
        presenter.view = view

        let nav = UINavigationController(rootViewController: view)
        BottomSheetViewFacade.setupBottomSheet(from: nav)

        return nav
    }
}
