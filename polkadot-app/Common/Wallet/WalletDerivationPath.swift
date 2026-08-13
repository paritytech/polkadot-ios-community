import Foundation
import KeyDerivation

/// Derivation paths of the built-in accounts. Product-account paths carry the 32-byte
/// index as a hex segment — always build them via `ProductDerivationPath`, never hand-format.
enum WalletDerivationPath {
    /// Main identity account `//product//uid.dot/{index_bytes(0)}`.
    static var main: String { ProductDerivationPath.builtInAccount(BuiltInProduct.uid, index: 0) }
    /// Game candidate account `//product//dim2.dot/{index_bytes(0)}`.
    static var candidate: String { ProductDerivationPath.builtInAccount(BuiltInProduct.dim2, index: 0) }
    /// Game score account `//product//dim2.dot/{index_bytes(1)}`.
    static var score: String { ProductDerivationPath.builtInAccount(BuiltInProduct.dim2, index: 1) }
    /// Deposit account `//product//fund.dot/{index_bytes(0)}`.
    static var deposit: String { ProductDerivationPath.builtInAccount(BuiltInProduct.fund, index: 0) }
    static var bulletInForChat: String { "//allowance//bulletin//chat" }
}
