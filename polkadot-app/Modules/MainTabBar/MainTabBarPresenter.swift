import UIKit
import PolkadotUI

@MainActor
final class MainTabBarPresenter {
    weak var view: MainTabBarViewProtocol?
    let wireframe: MainTabBarWireframeProtocol
    let interactor: MainTabBarInteractorInputProtocol

    // `.scan` must stay the centre slot: DSTabBarRow derives it as `itemCount / 2`, which holds
    // for both arms (index 2 of 5, index 2 of 4). The trailing slot in the non-products arm
    // balances `.scan` optically even when there are only four tabs.
    #if FEATURE_PRODUCTS
        let tabItems: [TabBarItem] = [.chat, .wallet, .scan, .browse, .settings]
    #else
        let tabItems: [TabBarItem] = [.chat, .wallet, .scan, .settings]
    #endif

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

    func didReceiveChainStatus(_ rows: [ChainConnectionStatusViewModel]) {
        view?.showChainStatus(rows)

        #if !FEATURE_PRODUCTS
            view?.showTabBarPanelContent(
                SwiftUIContentConfiguration(view: ChainConnectionStatusView(rows: rows)),
                trailingTint: trailingTint(for: rows)
            )
        #endif
    }
}

private extension MainTabBarPresenter {
    /// Worst state across the chains, so a single failing chain is visible without opening the panel.
    func trailingTint(for rows: [ChainConnectionStatusViewModel]) -> UIColor {
        if rows.contains(where: { $0.state == .offline }) {
            .bgStatusError
        } else if rows.contains(where: { $0.state == .connecting }) {
            .bgStatusWarning
        } else {
            .bgStatusSuccess
        }
    }
}
