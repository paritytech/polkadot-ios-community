import Foundation
import KeyDerivation
import SubstrateSdk

/// The `//datastore` sr25519 account that owns this seed's list in the `AccountDataStore` contract,
/// with the key its records are sealed under.
public struct DataStoreAccount: Sendable {
    public let privateKey: PrivateKey
    public let publicKey: PublicKey
    /// The pallet-revive H160 the contract keys the list by: the last 20 bytes of `keccak256(accountId)`.
    public let evmAccountId: Data
    public let encryptionKey: Data

    public var accountId: AccountId { publicKey }

    public init(privateKey: PrivateKey, publicKey: PublicKey, evmAccountId: Data, encryptionKey: Data) {
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.evmAccountId = evmAccountId
        self.encryptionKey = encryptionKey
    }
}

public protocol DataStoreAccountKeysProviding: Sendable {
    func account() async throws -> DataStoreAccount
}

/// Derives the data store account once from the root entropy and caches it.
public actor DataStoreAccountKeys: DataStoreAccountKeysProviding {
    public static let derivationPath = "//datastore"
    static let evmAccountIdSize = 20
    private static let encryptionContext = Data("encryption".utf8)

    private let entropyManager: RootEntropyManaging
    private var derived: DataStoreAccount?

    public init(entropyManager: RootEntropyManaging) {
        self.entropyManager = entropyManager
    }

    public func account() async throws -> DataStoreAccount {
        if let derived { return derived }

        let keypair = try WalletMnemonicKeypairFactory(
            derivationPath: Self.derivationPath,
            entropyManager: entropyManager
        ).deriveKeypair()
        let publicKey = keypair.publicKey().rawData()
        let secret = keypair.privateKey().rawData()

        let account = try DataStoreAccount(
            privateKey: secret,
            publicKey: publicKey,
            evmAccountId: Self.evmAccountId(for: publicKey),
            encryptionKey: Self.deriveEncryptionKey(sr25519Secret: secret)
        )
        derived = account
        return account
    }

    /// Keyed by the full 64-byte sr25519 secret — the scalar followed by its nonce — so Android derives
    /// the same key from the same `//datastore` keypair.
    public static func deriveEncryptionKey(sr25519Secret: Data) throws -> Data {
        try encryptionContext.blake2b32WithKey(sr25519Secret)
    }

    public static func evmAccountId(for accountId: AccountId) throws -> Data {
        try accountId.keccak256().suffix(evmAccountIdSize)
    }
}
