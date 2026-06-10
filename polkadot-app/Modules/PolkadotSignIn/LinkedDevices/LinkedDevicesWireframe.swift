import UIKit
import PolkadotUI

final class LinkedDevicesWireframe: LinkedDevicesWireframeProtocol {
    private let serviceCoordinator: ServiceCoordinatorProtocol

    init(serviceCoordinator: ServiceCoordinatorProtocol) {
        self.serviceCoordinator = serviceCoordinator
    }

    func showDeviceDetails(from view: LinkedDevicesViewProtocol?, device: Chat.LocalDevice) {
        guard let detailsView = DeviceDetailsViewFactory.createView(
            device: device,
            serviceCoordinator: serviceCoordinator
        ) else {
            return
        }

        view?.controller.navigationController?.pushViewController(
            detailsView.controller,
            animated: true
        )
    }

    func completeOpeningURL(from view: LinkedDevicesViewProtocol?, url: URL) {
        if view?.controller.presentedViewController != nil {
            view?.controller.dismiss(animated: true) {
                UIApplication.shared.open(url)
            }
        } else {
            UIApplication.shared.open(url)
        }
    }
}
