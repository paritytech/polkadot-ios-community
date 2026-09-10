import SwiftUI
import TipKit

struct ConnectionStatusActionTip: Tip {
    var title: Text { Text(verbatim: "Connection details") }

    var message: Text? { Text(verbatim: "Tap for per-chain connection details.") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
