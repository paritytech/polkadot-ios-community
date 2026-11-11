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
    func countTransfersStillSending()
    func decline(_ request: DeviceTransferRequest)
}

@MainActor
protocol DeviceTransferRequestInteractorOutputProtocol: AnyObject {
    func didReceive(pendingRequest: DeviceTransferRequest?)
    func didReceive(transfersStillSending: Int)
    func didDecline()
}

@MainActor
protocol DeviceTransferRequestWireframeProtocol: AnyObject {
    func close(from view: DeviceTransferRequestViewProtocol?)
    func closeAsWithdrawn(from view: DeviceTransferRequestViewProtocol?)
    func confirm(_ request: DeviceTransferRequest, from view: DeviceTransferRequestViewProtocol?)
    func warnAboutSendingTransfers(
        count: Int,
        from view: DeviceTransferRequestViewProtocol?,
        onConfirm: @escaping () -> Void
    )
}
