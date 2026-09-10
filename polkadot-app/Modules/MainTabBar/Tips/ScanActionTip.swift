import SwiftUI
import TipKit

struct ScanActionTip: Tip {
    var title: Text { Text(verbatim: "Scan a QR code") }

    var message: Text? { Text(verbatim: "Scan to pay, add a contact, or open a dApp.") }

    var image: Image? { Image(systemName: "qrcode.viewfinder") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
