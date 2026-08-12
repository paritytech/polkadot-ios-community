import Foundation
import KeyDerivation
import SubstrateSdk

enum IdentityAccountResolverError: Error {
    case accountMismatch
}

protocol IdentityAccountResolving {
    @discardableResult
    func resolveWallet(for accountId: AccountId) throws -> WalletManaging
}

struct IdentityAccountResolver: IdentityAccountResolving {
    private let identityWallet: WalletManaging

    init(identityWallet: WalletManaging = SelectedWallet.main) {
        self.identityWallet = identityWallet
    }

    @discardableResult
    func resolveWallet(for accountId: AccountId) throws -> WalletManaging {
        let identityAccountId = try identityWallet.getRawPublicKey()

        guard identityAccountId == accountId else {
            throw IdentityAccountResolverError.accountMismatch
        }

        return identityWallet
    }
}
