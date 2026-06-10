import Foundation
import KeyDerivation
import SubstrateSdk

public enum ProductAccountHolderError: Error {
    case failedToDeriveKeypair
    case notImplemented
}

public final class ProductAccountHolder: @unchecked Sendable {
    private let entropyManager: RootEntropyManaging

    public init(entropyManager: RootEntropyManaging) {
        self.entropyManager = entropyManager
    }
}

extension ProductAccountHolder: ProductAccountHolding {
    public func deriveAccount(_ productAccountId: ProductAccountId) throws -> AccountId {
        let wallet = DynamicDerivedWallet(
            derivationPath: productAccountId.derivationPath,
            entropyManager: entropyManager
        )
        return try wallet.getRawPublicKey()
    }

    public func deriveAlias(_ productAccountId: ProductAccountId) throws -> ProductsAlias {
        let context = try Data(productAccountId.derivationPath.utf8).blake2b32()

        let alias = try BandersnatchKeyManager(
            entropyDeriver: RootBandersnatchDeriver(),
            entropyManager: entropyManager
        )
        .deriveAlias(for: context)

        return ProductsAlias(context: context, alias: alias)
    }

    public func deriveStatementStoreAccount(for productId: ProductId) throws -> any WalletManaging {
        let path = Self.allowancePath(system: "statement-store", productId: productId)
        return DynamicDerivedWallet(derivationPath: path, entropyManager: entropyManager)
    }

    public func deriveStatementStorePrivateKey(for productId: ProductId) throws -> Data {
        let path = Self.allowancePath(system: "statement-store", productId: productId)
        return try derivePrivateKey(at: path)
    }

    public func deriveBulletInAccount(for productId: ProductId) throws -> any WalletManaging {
        let path = Self.allowancePath(system: "bulletin", productId: productId)
        return DynamicDerivedWallet(derivationPath: path, entropyManager: entropyManager)
    }

    public func deriveBulletInPrivateKey(for productId: ProductId) throws -> Data {
        let path = Self.allowancePath(system: "bulletin", productId: productId)
        return try derivePrivateKey(at: path)
    }

    public func deriveSmartContractAccount(
        for productId: ProductId,
        derivationIndex: UInt32
    ) throws -> any WalletManaging {
        let accountId = ProductAccountId(productId: productId, derivationIndex: derivationIndex)
        return DynamicDerivedWallet(
            derivationPath: accountId.derivationPath,
            entropyManager: entropyManager
        )
    }

    public func deriveAutoSigningSecrets(for _: ProductId) throws -> AutoSigningSecrets {
        throw ProductAccountHolderError.notImplemented
    }
}

private extension ProductAccountHolder {
    static func allowancePath(system: String, productId: ProductId) -> String {
        "//allowance//\(system)//\(productId)"
    }

    func derivePrivateKey(at path: String) throws -> Data {
        try WalletMnemonicKeypairFactory(derivationPath: path, entropyManager: entropyManager)
            .deriveKeypair()
            .privateKey()
            .rawData()
    }
}
