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
    var title: Text { Text(verbatim: "Network status") }
    var message: Text? { Text(verbatim: "These rings track your connection to each chain.") }
}

struct ChatTabTip: TabBarTip {
    var title: Text { Text(verbatim: "Chats live here") }
    var message: Text? { Text(verbatim: "Messages, calls, and contacts.") }
}

struct WalletTabTip: TabBarTip {
    var title: Text { Text(verbatim: "Your wallet") }
    var message: Text? { Text(verbatim: "Balances and transfers.") }
}

struct ScanActionTip: TabBarTip {
    var title: Text { Text(verbatim: "Scan a QR code") }
    var message: Text? { Text(verbatim: "Scan to pay or add a contact.") }
}

struct BrowseTabTip: TabBarTip {
    var title: Text { Text(verbatim: "Browse apps") }
    var message: Text? { Text(verbatim: "Discover dApps and open them in a tab.") }
}

struct SettingsTabTip: TabBarTip {
    var title: Text { Text(verbatim: "Settings") }
    var message: Text? { Text(verbatim: "Accounts, security, and preferences.") }
}

struct ConnectionStatusActionTip: TabBarTip {
    var title: Text { Text(verbatim: "Connection details") }
    var message: Text? { Text(verbatim: "Tap for per-chain connection details.") }
}
