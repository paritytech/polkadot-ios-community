import SwiftUI
import TipKit

struct SettingsTabTip: Tip {
    var title: Text { Text(verbatim: "Settings") }

    var message: Text? { Text(verbatim: "Accounts, security, and preferences.") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
