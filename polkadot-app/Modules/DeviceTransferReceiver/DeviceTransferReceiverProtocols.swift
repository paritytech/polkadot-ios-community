import PolkadotUI
import UIKitExt

@MainActor
protocol DeviceTransferReceiverViewProtocol: ControllerBackedProtocol {
    func didReceive(screen: DeviceTransferReceiverScreen, oldPhone: DeviceTransferPhone?)
    func didReceive(offersActivation: Bool)
}

@MainActor
protocol DeviceTransferReceiverPresenterProtocol: AnyObject {
    func setup()
    func startTransfer()
    func cancelTransfer()
    func activateWithoutTransfer()
    func complete()
}

@MainActor
protocol DeviceTransferReceiverInteractorInputProtocol: AnyObject {
    func setup()
    func startTransfer()
    func cancelTransfer()
    func activateWithoutTransfer()
}

@MainActor
protocol DeviceTransferReceiverInteractorOutputProtocol: AnyObject {
    func didReceive(state: DeviceTransferState)
    func didReceive(oldPhone: ActiveInstallation?)
    func didWaitTooLongForOldPhone()
    func didActivateWithoutTransfer()
    func didFailActivation()
}

@MainActor
protocol DeviceTransferReceiverWireframeProtocol: AlertPresentable {
    func complete()
}
