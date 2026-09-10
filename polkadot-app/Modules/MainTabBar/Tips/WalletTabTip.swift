import SwiftUI
import TipKit

struct WalletTabTip: Tip {
    var title: Text { Text(verbatim: "Your wallet") }

    var message: Text? { Text(verbatim: "Balances and transfers.") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
