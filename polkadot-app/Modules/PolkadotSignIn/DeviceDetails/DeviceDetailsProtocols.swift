import PolkadotUI
import UIKitExt

protocol DeviceDetailsViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: DeviceDetailsViewLayout.ViewModel)
}

protocol DeviceDetailsPresenterProtocol: AnyObject {
    func setup()
    func removeDevice()
}

protocol DeviceDetailsWireframeProtocol: AlertPresentable, ErrorPresentable {
    func showRemoveDevice(
        from view: DeviceDetailsViewProtocol?,
        device: Chat.LocalDevice,
        onResult: @escaping (Bool) -> Void
    )

    func close(from view: DeviceDetailsViewProtocol?)
}
