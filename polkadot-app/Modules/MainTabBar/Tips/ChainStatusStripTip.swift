import SwiftUI
import TipKit

struct ChainStatusStripTip: Tip {
    var title: Text { Text(verbatim: "Network status") }

    var message: Text? { Text(verbatim: "These rings track your connection to each chain.") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
