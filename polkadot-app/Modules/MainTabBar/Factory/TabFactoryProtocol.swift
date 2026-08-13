import UIKit
import Combine
import Keystore_iOS

@MainActor
protocol TabFactoryProtocol {
    func view(for item: TabBarItem) -> UIViewController?
}

final class TabFactory: TabFactoryProtocol {
    private let serviceCoordinator: ServiceCoordinatorProtocol
    private let flowState: ChatFlowState
    private weak var foregroundVisibilityReporter: PushForegroundVisibilityReporting?
    private let scanResultHandler: WalletQRScanDelegate

    init(
        serviceCoordinator: ServiceCoordinatorProtocol,
        flowState: ChatFlowState,
        scanResultHandler: WalletQRScanDelegate,
        foregroundVisibilityReporter: PushForegroundVisibilityReporting? = nil
    ) {
        self.serviceCoordinator = serviceCoordinator
        self.flowState = flowState
        self.scanResultHandler = scanResultHandler
        self.foregroundVisibilityReporter = foregroundVisibilityReporter
    }

    func view(for item: TabBarItem) -> UIViewController? {
        let mainContentVC: UIViewController? =
            switch item {
            case .chat:
                createChatTab()
            case .wallet:
                createWalletTab()
            case .scan:
                createScanTab()
            case .browse:
                createBrowseTab()
            case .settings:
                createSettingsTab()
            }

        return mainContentVC
    }
}

// MARK: Tab content

private extension TabFactory {
    private func createChatTab() -> UIViewController? {
        guard let view = ContactsListViewFactory.createView(flowState: flowState) else {
            return nil
        }

        let navigation = AppNavigationController(rootViewController: view.controller)

        navigation.barSettings = .shadowSettings
        navigation.scrollEdgeBarSettings = .defaultSettings

        return navigation
    }

    private func createWalletTab() -> UIViewController? {
        let context = WalletFlowContext(
            depositService: serviceCoordinator.depositService,
            fiatOnrampService: serviceCoordinator.fiatOnrampService,
            fiatOnrampTrackingService: serviceCoordinator.fiatOnrampTrackingService,
            coinageService: serviceCoordinator.coinageService,
            coinageBackupSyncService: serviceCoordinator.coinageBackupSyncService,
            personDataStore: serviceCoordinator.personDataStore,
            networkStatusService: serviceCoordinator.networkStatusService
        )
        guard let view = WalletMainViewFactory.createView(
            with: context,
            chainAssetId: AppConfig.Assets.mainAsset
        )
        else {
            return nil
        }

        let navigation = AppNavigationController(rootViewController: view.controller)

        navigation.barSettings = .shadowSettings
        navigation.scrollEdgeBarSettings = .defaultSettings
        return navigation
    }

    private func createBrowseTab() -> UIViewController? {
        guard let view = BrowseViewFactory.createBrowseRootView() else {
            return nil
        }

        let navigation = AppNavigationController(rootViewController: view.controller)

        navigation.barSettings = .shadowSettings
        navigation.scrollEdgeBarSettings = .defaultSettings

        return navigation
    }

    private func createSettingsTab() -> UIViewController? {
        guard let view = SettingsViewFactory.createView(
            serviceCoordinator: serviceCoordinator
        ) else {
            return nil
        }

        let navigation = AppNavigationController(rootViewController: view.controller)

        navigation.barSettings = .shadowSettings
        navigation.scrollEdgeBarSettings = .defaultSettings

        return navigation
    }

    private func createScanTab() -> UIViewController? {
        guard let view = WalletQRScanViewFactory.createView(for: scanResultHandler) else {
            return nil
        }
        return view.controller
    }
}
