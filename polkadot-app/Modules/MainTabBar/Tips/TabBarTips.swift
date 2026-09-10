import TipKit

enum TabBarTips {
    /// Transient: resets every launch, so no tip fires before the bar resolves its visibility.
    @Parameter(.transient)
    static var isBarShownAtRoot: Bool = false

    /// The tip chain in bar order. Single source of truth: the chrome builds its sequence from
    /// this, and Debug Settings resets eligibility across it.
    @MainActor
    static let steps: [TabBarTipStep] = [
        TabBarTipStep(tip: ChatTabTip(), slot: .tab(.chat)),
        TabBarTipStep(tip: WalletTabTip(), slot: .tab(.wallet)),
        TabBarTipStep(tip: ScanActionTip(), slot: .action(.scan)),
        TabBarTipStep(tip: SettingsTabTip(), slot: .tab(.settings))
    ]
}
