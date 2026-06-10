import Foundation
import PolkadotUI

final class MainTabBarPresenter {
    weak var view: MainTabBarViewProtocol?
    let wireframe: MainTabBarWireframeProtocol
    let interactor: MainTabBarInteractorInputProtocol

    var tabItems: [TabBarItem] = [.chat, .wallet, .browse, .settings]
    private var settingsBadge: TabBarBadge?

    init(
        interactor: MainTabBarInteractorInputProtocol,
        wireframe: MainTabBarWireframeProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension MainTabBarPresenter: MainTabBarPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func configureViews() {
        view?.show(tabs: tabItems)
        view?.select(tab: .wallet)
        view?.setBadge(settingsBadge, for: .settings)
    }
}

extension MainTabBarPresenter: MainTabBarInteractorOutputProtocol {
    func didUpdateSettingsAttention(isVisible: Bool) {
        let nextBadge = isVisible ? TabBarBadge.attention : nil
        guard settingsBadge != nextBadge else {
            return
        }
        settingsBadge = nextBadge
        view?.setBadge(settingsBadge, for: .settings)
    }

    func didReceiveWidget(
        configuration: any HashableContentConfiguration,
        for extensionId: ChatExtension.Id
    ) {
        view?.attachWidget(
            configuration,
            for: AppWidgetID(extensionId)
        )
    }

    func didRemoveWidget(for extensionId: ChatExtension.Id) {
        view?.detachWidget(for: AppWidgetID(extensionId))
    }

    func didReceivePolkadotSignInRequest(with url: URL) {
        wireframe.showPolkadotSignIn(with: url, view: view)
    }
}
