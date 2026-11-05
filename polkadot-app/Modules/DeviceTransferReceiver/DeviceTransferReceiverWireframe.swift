import Foundation
import PolkadotUI

final class DeviceTransferReceiverWireframe {
    /// Strong: once the first route is shown, nothing else keeps the root presenter alive.
    private let observer: RootStateObserving

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension DeviceTransferReceiverWireframe: DeviceTransferReceiverWireframeProtocol {
    /// Finalize saved this phone as active, so the root routes to the dashboard.
    func complete() {
        observer.didSettleInstallationStatus()
    }

    func showConfirmation(
        _ viewModel: DeviceTransferConfirmationViewLayout.ViewModel,
        from view: DeviceTransferReceiverViewProtocol?,
        onConfirm: @escaping () -> Void
    ) {
        let confirmation = DeviceTransferConfirmationViewFactory.createView(viewModel: viewModel, onConfirm: onConfirm)
        view?.controller.present(confirmation, animated: true)
    }
}
