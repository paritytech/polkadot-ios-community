import Foundation
import KeyDerivation
import SubstrateSdk

public protocol ProductAccountHolding: Sendable {
    func deriveAccount(_ productAccountId: ProductAccountId) throws -> AccountId

    func deriveAlias(_ productAccountId: ProductAccountId) throws -> ProductsAlias

    func deriveStatementStoreAccount(for productId: ProductId) throws -> any WalletManaging
    func deriveBulletInAccount(for productId: ProductId) throws -> any WalletManaging

    func deriveSmartContractAccount(
        for productId: ProductId,
        derivationIndex: UInt32
    ) throws -> any WalletManaging

    func deriveAutoSigningSecrets(for productId: ProductId) throws -> AutoSigningSecrets
}
