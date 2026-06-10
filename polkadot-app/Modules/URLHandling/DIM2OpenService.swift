import Foundation
import UIKit
import DesignSystem

final class DIM2OpenService {
    let host = "game"

    let serviceCoordinator: ServiceCoordinatorProtocol
    let logger: LoggerProtocol?

    init(
        serviceCoordinator: ServiceCoordinatorProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.serviceCoordinator = serviceCoordinator
        self.logger = logger
    }
}

extension DIM2OpenService: URLHandlingServiceProtocol {
    func handle(url: URL) -> Bool {
        guard url.host() == host else {
            return false
        }

        guard serviceCoordinator
            .chatExtensionsRegistry
            .getChatExtensionBot(for: DIM2ChatExtension.identifier) is DIM2ChatExtending
        else {
            return false
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let intendedGameIndex = components?.queryItems?
            .first(where: { $0.name == PushNotificationKeys.gameIndex })?
            .value
            .flatMap { UInt32($0) }
        let intendedGameId = intendedGameIndex.map { Game.Identifier(index: $0) }

        Task { @MainActor [serviceCoordinator, logger] in
            guard UIWindow.topWindow?.topmostViewController?.isPresentingGameVideo != true else {
                return
            }

            logger?.debug("Will open GameVideoViewFactory")

            guard let gameController = GameVideoViewFactory.createView(
                serviceCoordinator: serviceCoordinator,
                intendedGameId: intendedGameId
            )?.controller else {
                return
            }

            let navigationController = AppNavigationController(rootViewController: gameController)
            navigationController.modalPresentationStyle = .fullScreen
            navigationController.traitOverrides.appTheme = ThemesRegistry.default
            UIWindow.topWindow?.topmostViewController?.present(navigationController, animated: true)
        }
        return true
    }
}

private extension UIViewController {
    var isPresentingGameVideo: Bool {
        if self is GameVideoViewController {
            return true
        }

        let isGameVideoFlow = { (vc: UIViewController) in
            vc is GameVideoViewController || vc is GameReportViewController
        }

        if let nav = self as? UINavigationController,
           nav.viewControllers.contains(where: isGameVideoFlow) {
            return true
        }

        if let nav = navigationController,
           nav.viewControllers.contains(where: isGameVideoFlow) {
            return true
        }

        if presentingViewController?.isPresentingGameVideo == true {
            return true
        }

        return false
    }
}
