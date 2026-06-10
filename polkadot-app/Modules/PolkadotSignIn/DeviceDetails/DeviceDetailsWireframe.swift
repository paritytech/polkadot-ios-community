import UIKit
import PolkadotUI

final class DeviceDetailsWireframe: DeviceDetailsWireframeProtocol {
    private let serviceCoordinator: ServiceCoordinatorProtocol

    init(serviceCoordinator: ServiceCoordinatorProtocol) {
        self.serviceCoordinator = serviceCoordinator
    }

    func showRemoveDevice(
        from view: DeviceDetailsViewProtocol?,
        device: Chat.LocalDevice,
        onResult: @escaping (Bool) -> Void
    ) {
        let removeView = RemoveDeviceViewFactory.createView(
            device: device,
            serviceCoordinator: serviceCoordinator,
            onResult: onResult
        )

        view?.controller.present(removeView.controller, animated: true)
    }

    func close(from view: DeviceDetailsViewProtocol?) {
        view?.controller.navigationController?.popViewController(animated: true)
    }
}
