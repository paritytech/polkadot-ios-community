import Foundation
import PolkadotUI

@MainActor
enum DeviceTransferConfirmationViewFactory {
    static func createView(
        viewModel: DeviceTransferConfirmationViewLayout.ViewModel,
        onConfirm: @escaping () -> Void
    ) -> DeviceTransferConfirmationViewController {
        let viewController = DeviceTransferConfirmationViewController(viewModel: viewModel, onConfirm: onConfirm)
        BottomSheetViewFacade.setupBottomSheet(from: viewController)
        return viewController
    }
}
