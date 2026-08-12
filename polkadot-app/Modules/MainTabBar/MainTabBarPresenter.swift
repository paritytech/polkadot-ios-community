import Foundation
import PolkadotUI

@MainActor
final class MainTabBarPresenter {
    weak var view: MainTabBarViewProtocol?
    let wireframe: MainTabBarWireframeProtocol
    let interactor: MainTabBarInteractorInputProtocol

    let tabItems: [TabBarItem] = [.chat, .wallet, .scan, .browse, .settings]

    private let chipViewModelFactory: SPATabChipViewModelFactory
    private var settingsBadge: TabBarBadge?

    init(
        interactor: MainTabBarInteractorInputProtocol,
        wireframe: MainTabBarWireframeProtocol,
        chipViewModelFactory: SPATabChipViewModelFactory
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.chipViewModelFactory = chipViewModelFactory
    }
}

extension MainTabBarPresenter: MainTabBarPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func configureViews() {
        view?.show(tabs: tabItems, selecting: .wallet)
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

    func didReceiveSPATabs(_ tabs: [SPATab]) {
        view?.showSPATabs(chipViewModelFactory.createViewModels(for: tabs))
    }
}
