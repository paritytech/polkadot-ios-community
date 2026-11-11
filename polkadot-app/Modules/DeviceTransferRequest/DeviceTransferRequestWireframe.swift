import UIKit
import PolkadotUI

final class DeviceTransferRequestWireframe {
    /// Strong: once the first route is shown, nothing else keeps the root presenter alive.
    private let observer: RootStateObserving

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension DeviceTransferRequestWireframe: DeviceTransferRequestWireframeProtocol {
    func close(from view: DeviceTransferRequestViewProtocol?) {
        view?.controller.presentingViewController?.dismiss(animated: true)
    }

    func closeAsWithdrawn(from view: DeviceTransferRequestViewProtocol?) {
        let presenting = view?.controller.presentingViewController
        presenting?.dismiss(animated: true) {
            presenting?.showToast(message: String(localized: .deviceTransferRequestWithdrawn), type: .error)
        }
    }

    /// The root replaces the tab bar with the sender screens once the sheet is gone.
    func confirm(_ request: DeviceTransferRequest, from view: DeviceTransferRequestViewProtocol?) {
        view?.controller.presentingViewController?.dismiss(animated: true) { [observer] in
            observer.didConfirmDeviceTransfer(request)
        }
    }

    func warnAboutSendingTransfers(
        count: Int,
        from view: DeviceTransferRequestViewProtocol?,
        onConfirm: @escaping () -> Void
    ) {
        let confirmation = DeviceTransferConfirmationViewFactory.createView(
            viewModel: .sendingPayments(count: count),
            onConfirm: onConfirm
        )
        view?.controller.present(confirmation, animated: true)
    }
}
