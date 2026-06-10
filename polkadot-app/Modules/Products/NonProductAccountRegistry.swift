import Foundation
import SubstrateSdk
import KeyDerivation

protocol NonProductAccountRegistring {
    func getPublicKeys() throws -> [AccountId]
    func resolvedWallet(for accountId: AccountId) throws -> WalletManaging?
}

final class NonProductAccountRegistry {
    let wallets: [WalletManaging]

    init(wallets: [WalletManaging]) {
        self.wallets = wallets
    }
}

extension NonProductAccountRegistry: NonProductAccountRegistring {
    func getPublicKeys() throws -> [AccountId] {
        try wallets.map { try $0.getRawPublicKey() }
    }

    func resolvedWallet(for accountId: AccountId) throws -> WalletManaging? {
        try wallets.first { wallet in
            let walletAccountId = try wallet.getRawPublicKey()

            return accountId == walletAccountId
        }
    }
}

extension NonProductAccountRegistry {
    static var main: NonProductAccountRegistring {
        NonProductAccountRegistry(wallets: [SelectedWallet.main])
    }
}
