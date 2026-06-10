import Foundation
import Individuality

enum WalletDerivationPath {
    static var main: String { "//wallet" }
    static var candidate: String { "//candidate" }
    static var score: String { "//\(PalletContext.score)" }
    static var deposit: String { "//wallet//deposit" }
    static var bulletInForChat: String { "//allowance//bulletin//chat" }
}
