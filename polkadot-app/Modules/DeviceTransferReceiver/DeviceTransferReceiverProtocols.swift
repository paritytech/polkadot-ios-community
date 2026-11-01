import PolkadotUI
import UIKitExt

protocol DeviceTransferReceiverViewProtocol: ControllerBackedProtocol {}

protocol DeviceTransferReceiverPresenterProtocol: AnyObject {
    func setup()
}

protocol DeviceTransferReceiverInteractorInputProtocol: AnyObject {}

@MainActor
protocol DeviceTransferReceiverInteractorOutputProtocol: AnyObject {}

protocol DeviceTransferReceiverWireframeProtocol: AnyObject, AlertPresentable, ErrorPresentable {}
