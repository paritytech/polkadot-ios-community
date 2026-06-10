import UIKit
import PolkadotUI

final class MainTabBarWireframe: MainTabBarWireframeProtocol {
    private let serviceCoordinator: ServiceCoordinatorProtocol

    init(serviceCoordinator: ServiceCoordinatorProtocol) {
        self.serviceCoordinator = serviceCoordinator
    }

    func showPolkadotSignIn(with url: URL, view: MainTabBarViewProtocol?) {
        guard let signInView = PolkadotSignInViewFactory.createView(
            serviceCoordinator: serviceCoordinator,
            url: url,
            onResult: { [weak self, weak view] result in
                self?.handleSignInResult(result, view: view)
            }
        ) else {
            return
        }
        view?.controller.present(signInView.controller, animated: true)
    }
}

private extension MainTabBarWireframe {
    func handleSignInResult(_ result: PolkadotSignInResult, view: MainTabBarViewProtocol?) {
        switch result {
        case let .success(device):
            view?.controller.showToast(
                message: String(localized: .linkedDevicesSignInDeviceConnected),
                type: .success
            )
            showDeviceDetails(device, view: view)
        case let .noFreeSlots(message):
            let controller = NoSlotsAvailableViewFactory.createView(message: message)
            view?.controller.present(controller, animated: true)
        case .failed:
            view?.controller.showToast(
                message: String(localized: .linkedDevicesSignInError),
                type: .error
            )
        }
    }

    func showDeviceDetails(_ device: Chat.LocalDevice, view: MainTabBarViewProtocol?) {
        guard let detailsView = DeviceDetailsViewFactory.createView(
            device: device,
            serviceCoordinator: serviceCoordinator
        ) else {
            return
        }
        let tabBarController = view?.controller as? UITabBarController
        let navigationController = tabBarController?.selectedViewController as? UINavigationController
        navigationController?.pushViewController(detailsView.controller, animated: true)
    }
}
