import UIKit
import PolkadotUI

final class DeviceTransferSenderWireframe {
    /// Strong: once the first route is shown, nothing else keeps the root presenter alive.
    private let observer: RootStateObserving

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension DeviceTransferSenderWireframe: DeviceTransferSenderWireframeProtocol {
    /// The root reads the saved status: the dashboard while this phone is active, the receiver once replaced.
    func complete() {
        observer.didSettleInstallationStatus()
    }

    func showConfirmation(
        _ viewModel: DeviceTransferConfirmationViewLayout.ViewModel,
        from view: DeviceTransferSenderViewProtocol?,
        onConfirm: @escaping () -> Void
    ) {
        let confirmation = DeviceTransferConfirmationViewFactory.createView(viewModel: viewModel, onConfirm: onConfirm)
        view?.controller.present(confirmation, animated: true)
    }

    func completeAfterFailure(from view: DeviceTransferSenderViewProtocol?) {
        let window = view?.controller.view.window
        observer.didSettleInstallationStatus()
        window?.rootViewController?.showToast(message: String(localized: .deviceTransferSenderFailed), type: .error)
    }
}
