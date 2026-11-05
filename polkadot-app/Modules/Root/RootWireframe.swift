import UIKit

final class RootWireframe: RootWireframeProtocol {
    let window: UIWindow
    let animation = RootControllerAnimationCoordinator()
    private let dashboardDependencies: MainTabBarDependencies

    init(
        window: UIWindow,
        userNotificationService: UserNotificationServicing,
        foregroundVisibilityReporter: PushForegroundVisibilityReporting?,
        deepLinkHandling: DeferredLinkHandling,
        flowStateProvider: any SPAFlowStateProviding
    ) {
        self.window = window
        dashboardDependencies = MainTabBarDependencies(
            userNotificationService: userNotificationService,
            foregroundVisibilityReporter: foregroundVisibilityReporter,
            deepLinkHandling: deepLinkHandling,
            flowStateProvider: flowStateProvider
        )
    }

    func showDashboard(with observer: RootStateObserving) {
        guard let dashboard = MainTabBarViewFactory.createView(
            dependencies: dashboardDependencies,
            observer: observer,
            windowScene: window.windowScene
        ) else {
            return
        }

        animation.animateTransition(to: dashboard.controller, in: window)
    }

    func showOnboarding(with observer: RootStateObserving) {
        guard let usernameView = ClaimUsernameViewFactory.createLiteClaimView(observer: observer) else {
            return
        }

        let viewContainer = AppNavigationController(rootViewController: usernameView.controller)

        animation.animateTransition(to: viewContainer, in: window)
    }

    func showRestoreFromCloud(with observer: RootStateObserving) {
        guard let restoreFromCloudView = RestoreFromCloudViewFactory.createView(with: observer) else {
            return
        }

        animation.animateTransition(to: restoreFromCloudView.controller, in: window)
    }

    func showUsernameClaim(with observer: RootStateObserving) {
        guard let usernameView = ClaimUsernameViewFactory.createLiteClaimView(observer: observer) else {
            return
        }

        let viewContainer = AppNavigationController(rootViewController: usernameView.controller)

        animation.animateTransition(to: viewContainer, in: window)
    }

    func showThemeSelection(with observer: RootStateObserving) {
        let view = ThemeSelectionViewFactory.createView(observer: observer)
        animation.animateTransition(to: view, in: window)
    }

    func showInstallationCheck(with observer: RootStateObserving) {
        let view = InstallationCheckViewFactory.createView(observer: observer)
        animation.animateTransition(to: view.controller, in: window)
    }

    func showDeviceTransfer(with observer: RootStateObserving) {
        let view = DeviceTransferReceiverViewFactory.createView(observer: observer)
        animation.animateTransition(to: view.controller, in: window)
    }

    func showDeviceTransferSender(for request: DeviceTransferRequest, with observer: RootStateObserving) {
        let view = DeviceTransferSenderViewFactory.createView(request: request, observer: observer)
        animation.animateTransition(to: view.controller, in: window)
    }

    func showBroken() {
        // normally user must not see this but on malicious devices it is possible
        let brokenController = UIViewController()
        brokenController.view.backgroundColor = .red

        animation.animateTransition(to: brokenController, in: window)
    }

    func showUsernameCheck(with observer: RootStateObserving) {
        guard
            let destination = CheckUsernameViewFactory.createView(with: observer)
        else {
            return
        }

        animation.animateTransition(to: destination.controller, in: window)
    }
}

#if TESTNET_FEATURE
    extension RootWireframe {
        func showAppFactoryResetSheet() {
            guard let presenter = window.topmostViewController ?? window.rootViewController else {
                return
            }

            let sheetView = AppFactoryResetViewFactory.createView()
            presenter.present(sheetView.controller, animated: true)
        }
    }
#endif
