import UIKit

public extension UIWindow {
    class var topWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }

    class var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    var topmostViewController: UIViewController? {
        topmost(of: rootViewController)
    }

    private func topmost(of viewController: UIViewController?) -> UIViewController? {
        if let navigationController = viewController as? UINavigationController {
            return topmost(of: navigationController.visibleViewController)
        }

        if let tabBarController = viewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return topmost(of: selectedViewController)
        }

        if let presentedViewController = viewController?.presentedViewController {
            return topmost(of: presentedViewController)
        }

        return viewController
    }
}
