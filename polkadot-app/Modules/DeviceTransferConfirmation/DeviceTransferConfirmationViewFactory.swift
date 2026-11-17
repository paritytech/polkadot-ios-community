import Foundation
import PolkadotUI

@MainActor
enum DeviceTransferConfirmationViewFactory {
    static func createView(
        viewModel: DeviceTransferConfirmationViewLayout.ViewModel,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void = {}
    ) -> DeviceTransferConfirmationViewController {
        let viewController = DeviceTransferConfirmationViewController(
            viewModel: viewModel,
            onConfirm: onConfirm,
            onDismiss: onDismiss
        )
        BottomSheetViewFacade.setupBottomSheet(from: viewController)
        return viewController
    }
}
