import UIKit

final class RootWireframe: RootWireframeProtocol {
    let window: UIWindow
    let animation = RootControllerAnimationCoordinator()
    private let userNotificationService: UserNotificationServicing
    private weak var foregroundVisibilityReporter: PushForegroundVisibilityReporting?
    private let deepLinkHandler: DeferredLinkHandling

    init(
        window: UIWindow,
        userNotificationService: UserNotificationServicing,
        foregroundVisibilityReporter: PushForegroundVisibilityReporting?,
        deepLinkHandling: DeferredLinkHandling
    ) {
        self.window = window
        self.userNotificationService = userNotificationService
        self.foregroundVisibilityReporter = foregroundVisibilityReporter
        deepLinkHandler = deepLinkHandling
    }

    func showDashboard() {
        guard let dashboard = MainTabBarViewFactory.createView(
            userNotificationService: userNotificationService,
            foregroundVisibilityReporter: foregroundVisibilityReporter,
            deepLinkHandling: deepLinkHandler
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

    func showW3SSpa(with observer: RootStateObserving) {
        guard let view = Web3SummitSpaViewFactory.createView(observer: observer) else {
            return
        }

        animation.animateTransition(to: view.controller, in: window)
    }

    func showW3SEnded() {
        let view = Web3SummitHardGateViewFactory.createEndedView()
        animation.animateTransition(to: view, in: window)
    }

    func showW3SNotStarted() {
        let view = Web3SummitHardGateViewFactory.createNotStartedView()
        animation.animateTransition(to: view, in: window)
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

    func showJailbroken() {
        guard let rootViewController = window.topmostViewController ?? window.rootViewController else {
            return
        }

        let alert = UIAlertController(
            title: String(localized: .Security.jailbreakDetectedTitle),
            message: String(localized: .Security.jailbreakDetectedDescription),
            preferredStyle: .alert
        )

        let exitAction = UIAlertAction(title: "Exit", style: .destructive) { _ in
            exit(0)
        }

        alert.addAction(exitAction)
        rootViewController.present(alert, animated: true)
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
