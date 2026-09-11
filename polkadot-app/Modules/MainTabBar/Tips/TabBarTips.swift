import TipKit

enum TabBarTips {
    /// Transient: resets every launch, so no tip fires before the bar resolves its visibility.
    @Parameter(.transient)
    static var isBarShownAtRoot: Bool = false

    /// The tip chain: the top status strip first, then the bar left to right. Branches on
    /// `FEATURE_PRODUCTS` the same way `MainTabBarPresenter.slots` does — Browse exists only in
    /// that arm, the connection-status action only in the other. Single source of truth: the
    /// chrome builds its sequence from this, and Debug Settings resets eligibility across it.
    @MainActor
    static let steps: [TabBarTipStep] = {
        let head: [TabBarTipStep] = [
            TabBarTipStep(tip: ChainStatusStripTip(), anchor: .statusStrip),
            TabBarTipStep(tip: ChatTabTip(), anchor: .barItem(.tab(.chat))),
            TabBarTipStep(tip: WalletTabTip(), anchor: .barItem(.tab(.wallet))),
            TabBarTipStep(tip: ScanActionTip(), anchor: .barItem(.action(.scan)))
        ]

        #if FEATURE_PRODUCTS
            return head + [
                TabBarTipStep(tip: BrowseTabTip(), anchor: .barItem(.tab(.browse))),
                TabBarTipStep(tip: SettingsTabTip(), anchor: .barItem(.tab(.settings)))
            ]
        #else
            return head + [
                TabBarTipStep(tip: SettingsTabTip(), anchor: .barItem(.tab(.settings))),
                TabBarTipStep(tip: ConnectionStatusActionTip(), anchor: .barItem(.action(.connectionStatus)))
            ]
        #endif
    }()
}
