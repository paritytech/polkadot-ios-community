import PolkadotUI
import UIKitExt

@MainActor
protocol DeviceTransferSenderViewProtocol: ControllerBackedProtocol {}

@MainActor
protocol DeviceTransferSenderPresenterProtocol: AnyObject {
    func setup()
}

@MainActor
protocol DeviceTransferSenderInteractorInputProtocol: AnyObject {}

@MainActor
protocol DeviceTransferSenderInteractorOutputProtocol: AnyObject {}

@MainActor
protocol DeviceTransferSenderWireframeProtocol: AnyObject {}
