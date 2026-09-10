import SwiftUI
import TipKit

struct ChatTabTip: Tip {
    var title: Text { Text(verbatim: "Chats live here") }

    var message: Text? { Text(verbatim: "Messages, calls, and contacts.") }

    var image: Image? { Image(systemName: "bubble.left.and.bubble.right") }

    var rules: [Rule] {
        #Rule(TabBarTips.$isBarShownAtRoot) { $0 == true }
    }

    var options: [any Option] { MaxDisplayCount(1) }
}
