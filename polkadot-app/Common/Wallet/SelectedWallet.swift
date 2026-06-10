import Foundation
import Keystore_iOS
import Individuality
import KeyDerivation

enum SelectedWallet {
    private(set) static var main = DynamicDerivedWallet(derivationPath: WalletDerivationPath.main)
    private(set) static var candidate = DynamicDerivedWallet(derivationPath: WalletDerivationPath.candidate)
    private(set) static var mobRuleAlias = DynamicDerivedWallet(derivationPath: "//\(PalletContext.mobRule)")
    private(set) static var scoreAlias = DynamicDerivedWallet(derivationPath: WalletDerivationPath.score)
    private(set) static var internalPayout = DynamicDerivedWallet(derivationPath: "//\(PalletContext.privacyVoucher)")
    private(set) static var resourcesAlias = DynamicDerivedWallet(derivationPath: "//\(PalletContext.resources)")
    private(set) static var depositWallet = DynamicDerivedWallet(derivationPath: WalletDerivationPath.deposit)
    private(set) static var bulletInForChat = DynamicDerivedWallet(derivationPath: WalletDerivationPath.bulletInForChat)
}

#if TESTNET_FEATURE
    extension SelectedWallet {
        static func resetAll() {
            main = DynamicDerivedWallet(derivationPath: WalletDerivationPath.main)
            candidate = DynamicDerivedWallet(derivationPath: WalletDerivationPath.candidate)
            mobRuleAlias = DynamicDerivedWallet(derivationPath: "//\(PalletContext.mobRule)")
            scoreAlias = DynamicDerivedWallet(derivationPath: WalletDerivationPath.score)
            internalPayout = DynamicDerivedWallet(derivationPath: "//\(PalletContext.privacyVoucher)")
            resourcesAlias = DynamicDerivedWallet(derivationPath: "//\(PalletContext.resources)")
            depositWallet = DynamicDerivedWallet(derivationPath: WalletDerivationPath.deposit)
            bulletInForChat = DynamicDerivedWallet(derivationPath: WalletDerivationPath.bulletInForChat)
        }
    }
#endif
