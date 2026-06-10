import UIKit
import PolkadotUI
import UIKitExt

protocol MainTabBarViewProtocol: ControllerBackedProtocol, AppWidgetManaging {
    func show(tabs: [TabBarItem])
    func select(tab: TabBarItem)
    func setBadge(_ badge: TabBarBadge?, for tab: TabBarItem)
}

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
}

protocol MainTabBarWireframeProtocol: AnyObject {
    func showPolkadotSignIn(with url: URL, view: MainTabBarViewProtocol?)
}

enum TabBarItem: CaseIterable {
    case chat
    case wallet
    case browse
    case settings

    var index: Int {
        switch self {
        case .chat: 0
        case .wallet: 1
        case .browse: 2
        case .settings: 3
        }
    }

    var image: UIImage {
        let asset: UIImage =
            switch self {
            case .chat: .tabChat
            case .wallet: .tabWallet
            case .browse: .tabBrowse
            case .settings: .tabSettings
            }
        return asset.withRenderingMode(.alwaysTemplate)
    }

    var title: String {
        switch self {
        case .chat: String(localized: .tabChat)
        case .wallet: String(localized: .tabWallet)
        case .browse: String(localized: .tabBrowse)
        case .settings: String(localized: .tabSettings)
        }
    }
}

enum TabBarBadge: Equatable {
    case attention
}
