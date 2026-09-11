import SwiftUI
import TipKit

/// Every tab bar tip waits for the bar to be on screen at a tab root and shows once.
/// Each stays a distinct type: TipKit keys display state and eligibility by type.
protocol TabBarTip: Tip {}

extension TabBarTip {
    var rules: [Rule] {
        [#Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }]
    }

    var options: [any Option] { [MaxDisplayCount(1)] }
}

struct ChainStatusStripTip: TabBarTip {
    var title: Text { Text(.Tips.chainStatusTitle) }
    var message: Text? { Text(.Tips.chainStatusMessage) }
}

struct ChatTabTip: TabBarTip {
    var title: Text { Text(.Tips.chatTitle) }
    var message: Text? { Text(.Tips.chatMessage) }
}

struct WalletTabTip: TabBarTip {
    var title: Text { Text(.Tips.walletTitle) }
    var message: Text? { Text(.Tips.walletMessage) }
}

struct ScanActionTip: TabBarTip {
    var title: Text { Text(.Tips.scanTitle) }
    var message: Text? { Text(.Tips.scanMessage) }
}

struct BrowseTabTip: TabBarTip {
    var title: Text { Text(.Tips.browseTitle) }
    var message: Text? { Text(.Tips.browseMessage) }
}

struct SettingsTabTip: TabBarTip {
    var title: Text { Text(.Tips.settingsTitle) }
    var message: Text? { Text(.Tips.settingsMessage) }
}

struct ConnectionStatusActionTip: TabBarTip {
    var title: Text { Text(.Tips.connectionStatusTitle) }
    var message: Text? { Text(.Tips.connectionStatusMessage) }
}
