import SwiftUI
import TipKit

struct ScanActionTip: Tip {
    var title: Text { Text(verbatim: "Scan a QR code") }

    var message: Text? { Text(verbatim: "Scan to pay or add a contact.") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
