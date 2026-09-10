import SwiftUI
import TipKit

struct BrowseTabTip: Tip {
    var title: Text { Text(verbatim: "Browse apps") }

    var message: Text? { Text(verbatim: "Discover dApps and open them in a tab.") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
