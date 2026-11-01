import PolkadotUI
import UIKitExt

@MainActor
protocol DeviceTransferReceiverViewProtocol: ControllerBackedProtocol {
    func didReceive(screen: DeviceTransferReceiverScreen, oldPhone: DeviceTransferOldPhone?)
}

@MainActor
protocol DeviceTransferReceiverPresenterProtocol: AnyObject {
    func setup()
    func startTransfer()
    func cancelTransfer()
    func complete()
}

@MainActor
protocol DeviceTransferReceiverInteractorInputProtocol: AnyObject {
    func setup()
    func startTransfer()
    func cancelTransfer()
}

@MainActor
protocol DeviceTransferReceiverInteractorOutputProtocol: AnyObject {
    func didReceive(state: DeviceTransferState)
    func didReceive(oldPhone: ActiveInstallation?)
}

@MainActor
protocol DeviceTransferReceiverWireframeProtocol: AnyObject {
    func complete()
}
