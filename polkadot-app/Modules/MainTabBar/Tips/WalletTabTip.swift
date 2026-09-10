import SwiftUI
import TipKit

struct WalletTabTip: Tip {
    var title: Text { Text(verbatim: "Your wallet") }

    var message: Text? { Text(verbatim: "Balances, transfers, and history.") }

    var image: Image? { Image(systemName: "creditcard") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
