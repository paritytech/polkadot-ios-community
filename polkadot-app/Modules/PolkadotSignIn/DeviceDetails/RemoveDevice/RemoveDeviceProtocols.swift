import PolkadotUI
import UIKitExt

protocol RemoveDeviceViewProtocol: ControllerBackedProtocol {
    func didReceive(deviceDescription: String)
    func didReceive(isLoading: Bool)
}

protocol RemoveDevicePresenterProtocol: AnyObject {
    func setup()
    func confirm()
    func cancel()
}

protocol RemoveDeviceInteractorInputProtocol: AnyObject {
    func removeDevice(identifier: String)
}

protocol RemoveDeviceInteractorOutputProtocol: AnyObject {
    func didRemoveDevice()
    func didFailToRemoveDevice(error: Error)
}

protocol RemoveDeviceWireframeProtocol: AnyObject {
    func close(view: RemoveDeviceViewProtocol?, completion: (() -> Void)?)
}
