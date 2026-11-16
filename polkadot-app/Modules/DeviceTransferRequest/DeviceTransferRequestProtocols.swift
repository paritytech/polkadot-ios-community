import PolkadotUI
import UIKitExt

@MainActor
protocol DeviceTransferRequestViewProtocol: ControllerBackedProtocol {
    func didReceive(newPhone: DeviceTransferPhone)
}

@MainActor
protocol DeviceTransferRequestPresenterProtocol: AnyObject {
    func setup()
    func transfer()
    func decline()
}

@MainActor
protocol DeviceTransferRequestInteractorInputProtocol: AnyObject {
    func setup()
    func countPendingPayments()
    func decline(_ request: DeviceTransferRequest)
}

@MainActor
protocol DeviceTransferRequestInteractorOutputProtocol: AnyObject {
    func didReceive(pendingRequest: DeviceTransferRequest?)
    func didReceive(pendingPayments: PendingPayments)
    func didDecline()
}

@MainActor
protocol DeviceTransferRequestWireframeProtocol: AnyObject {
    func close(from view: DeviceTransferRequestViewProtocol?)
    func closeAsWithdrawn(from view: DeviceTransferRequestViewProtocol?)
    func confirm(_ request: DeviceTransferRequest, from view: DeviceTransferRequestViewProtocol?)
    /// Replaces the request sheet with the pending-payments warning; the closures answer the request.
    func warnPendingPayments(
        from view: DeviceTransferRequestViewProtocol?,
        onTransferAnyway: @escaping () -> Void,
        onDecline: @escaping () -> Void
    )
}
