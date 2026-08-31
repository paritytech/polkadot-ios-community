import UIKit
import PolkadotUI
import UIKitExt
import ExternalAccessibility
import Products

protocol MainTabBarViewProtocol: ControllerBackedProtocol, AppWidgetManaging {
    func show(tabs: [TabBarItem], selecting tab: TabBarItem)
    func select(tab: TabBarItem)
    func setBadge(_ badge: TabBarBadge?, for tab: TabBarItem)
    func showSPATabs(_ viewModels: [SPATabChipViewModel])
    func showTabBarPanelContent(_ configuration: (any HashableContentConfiguration)?)
}

@MainActor
protocol MainTabBarPresenterProtocol: AnyObject {
    func setup()
    func configureViews()
}

protocol MainTabBarInteractorInputProtocol: AnyObject {
    func setup()
}

@MainActor
protocol MainTabBarInteractorOutputProtocol: AnyObject {
    func didUpdateSettingsAttention(isVisible: Bool)
    func didReceiveWidget(
        configuration: any HashableContentConfiguration,
        for extensionId: ChatExtension.Id
    )
    func didRemoveWidget(for extensionId: ChatExtension.Id)
    func didReceivePolkadotSignInRequest(with url: URL)
    func didReceiveSPATabs(_ tabs: [SPATab])
    func didReceiveChainStatus(_ configuration: any HashableContentConfiguration)
}

@MainActor
protocol MainTabBarWireframeProtocol: AnyObject {
    func showPolkadotSignIn(with url: URL, view: MainTabBarViewProtocol?)
}

enum TabBarItem: String, CaseIterable {
    case chat
    case wallet
    case scan
    case browse
    case settings

    var image: UIImage {
        let asset: UIImage =
            switch self {
            case .chat: .tabChat
            case .wallet: .tabWallet
            case .scan: .tabScan
            case .browse: .tabBrowse
            case .settings: .tabSettings
            }
        return asset.withRenderingMode(.alwaysTemplate)
    }

    var title: String {
        switch self {
        case .chat: String(localized: .tabChat)
        case .wallet: String(localized: .tabWallet)
        case .scan: String(localized: .tabScan)
        case .browse: String(localized: .tabBrowse)
        case .settings: String(localized: .tabSettings)
        }
    }
}

enum TabBarBadge: Equatable {
    case attention
}

extension TabBarItem {
    var displayTitle: String? {
        self == .scan ? nil : title
    }

    func makeBarItem(badge: TabBarBadge?) -> DSTabBarItem {
        DSTabBarItem(
            icon: image,
            title: displayTitle,
            badge: badge.map { _ in .attention },
            accessibilityLabel: title,
            accessibilityIdentifier: AccessibilityID.Tab.item(for: self)?.rawValue
        )
    }
}

enum TabBarTrailingSlotFactory {
    static func makeSlot() -> DSTabBarTrailingSlot? {
        guard let icon = UIImage(systemName: "point.3.connected.trianglepath.dotted") else {
            return nil
        }
        return DSTabBarTrailingSlot(
            icon: icon.withRenderingMode(.alwaysTemplate),
            accessibilityLabel: String(localized: .Common.tabBarPanelAccessibility)
        )
    }
}

@MainActor
protocol SPAHosting: AnyObject {
    func openProduct(page: ProductPage)
    func minimizeSPA()
    func closeSPA(tabId: UUID)
}
