import UIKit
import Combine
import Keystore_iOS
import DesignSystem

@MainActor
protocol TabFactoryProtocol {
    func view(for item: TabBarItem) -> UIViewController?
    func tabBarItem(for item: TabBarItem, badge: TabBarBadge?) -> UITabBarItem
}

final class TabFactory: TabFactoryProtocol {
    private let serviceCoordinator: ServiceCoordinatorProtocol
    private let flowState: ChatFlowState
    private weak var foregroundVisibilityReporter: PushForegroundVisibilityReporting?

    init(
        serviceCoordinator: ServiceCoordinatorProtocol,
        flowState: ChatFlowState,
        foregroundVisibilityReporter: PushForegroundVisibilityReporting? = nil
    ) {
        self.serviceCoordinator = serviceCoordinator
        self.flowState = flowState
        self.foregroundVisibilityReporter = foregroundVisibilityReporter
    }

    func view(for item: TabBarItem) -> UIViewController? {
        let mainContentVC: UIViewController? =
            switch item {
            case .chat:
                createChatTab()
            case .wallet:
                createWalletTab()
            case .browse:
                createBrowseTab()
            case .settings:
                createSettingsTab()
            }

        mainContentVC?.tabBarItem = createTabBarItem(for: item)
        return mainContentVC
    }

    func tabBarItem(for item: TabBarItem, badge: TabBarBadge?) -> UITabBarItem {
        if let badge {
            createTabBarItemWithBadge(for: item, badge: badge)
        } else {
            createTabBarItem(for: item)
        }
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
            personDataStore: serviceCoordinator.personDataStore
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

    private func createTabBarItem(for item: TabBarItem) -> UITabBarItem {
        let normalImage = item.image
            .tinted(with: .fgSecondary)?
            .withRenderingMode(.alwaysOriginal)
        let selectedImage = item.image
            .tinted(with: .fgPrimary)?
            .withRenderingMode(.alwaysOriginal)

        let tabBarItem = UITabBarItem(
            title: item.title,
            image: normalImage ?? item.image,
            selectedImage: selectedImage ?? item.image
        )
        tabBarItem.tag = item.index
        return tabBarItem
    }

    func createTabBarItemWithBadge(for item: TabBarItem, badge: TabBarBadge) -> UITabBarItem {
        let badgeColor: UIColor =
            switch badge {
            case .attention:
                .bgStatusWarning
            }

        let normalImage = composedBadgeImage(
            from: item.image,
            iconTint: .fgSecondary,
            badgeColor: badgeColor
        )
        let selectedImage = composedBadgeImage(
            from: item.image,
            iconTint: .fgPrimary,
            badgeColor: badgeColor
        )

        let tabBarItem = UITabBarItem(
            title: item.title,
            image: normalImage ?? item.image,
            selectedImage: selectedImage ?? item.image
        )
        tabBarItem.tag = item.index
        return tabBarItem
    }

    func composedBadgeImage(
        from icon: UIImage,
        iconTint: UIColor,
        badgeColor: UIColor
    ) -> UIImage? {
        icon
            .tinted(with: iconTint)?
            .withAttentionBadge(
                badgeColor: badgeColor,
                badgeRadius: 4,
                badgeOffset: CGPoint(x: -3, y: 4)
            )?
            .withRenderingMode(.alwaysOriginal)
    }
}
