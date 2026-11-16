import UIKit
import PolkadotUI

final class DeviceTransferRequestWireframe {
    /// Strong: once the first route is shown, nothing else keeps the root presenter alive.
    private let observer: RootStateObserving
    /// The request sheet is gone while the warning is up, so a withdrawal has to close the warning instead.
    private weak var pendingPaymentsWarning: UIViewController?

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension DeviceTransferRequestWireframe: DeviceTransferRequestWireframeProtocol {
    func close(from view: DeviceTransferRequestViewProtocol?) {
        view?.controller.presentingViewController?.dismiss(animated: true)
    }

    func closeAsWithdrawn(from view: DeviceTransferRequestViewProtocol?) {
        let presenting = (view?.controller ?? pendingPaymentsWarning)?.presentingViewController
        presenting?.dismiss(animated: true) {
            presenting?.showToast(message: String(localized: .deviceTransferRequestWithdrawn), type: .error)
        }
    }

    /// The root replaces the tab bar with the sender screens once the sheet is gone. Without a view the
    /// warning sheet has already dismissed itself.
    func confirm(_ request: DeviceTransferRequest, from view: DeviceTransferRequestViewProtocol?) {
        guard let presenting = view?.controller.presentingViewController else {
            observer.didConfirmDeviceTransfer(request)
            return
        }
        presenting.dismiss(animated: true) { [observer] in
            observer.didConfirmDeviceTransfer(request)
        }
    }

    func warnPendingPayments(
        from view: DeviceTransferRequestViewProtocol?,
        onTransferAnyway: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        let presenting = view?.controller.presentingViewController
        presenting?.dismiss(animated: true) { [weak self] in
            let warning = DeviceTransferConfirmationViewFactory.createView(
                viewModel: .pendingPayments,
                onConfirm: onTransferAnyway,
                onDismiss: onDecline
            )
            self?.pendingPaymentsWarning = warning
            presenting?.present(warning, animated: true)
        }
    }
}
