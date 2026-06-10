import Foundation
import SubstrateSdk
import NovaCrypto

public final class WalletMnemonicKeypairFactory {
    let derivationPath: String?
    let mnemonicProvider: WalletMnemonicProviding

    private lazy var junctionFactory: JunctionFactoryProtocol = SubstrateJunctionFactory()
    private lazy var seedFactory: SeedFactoryProtocol = SeedFactory()
    private lazy var keypairFactory: KeypairFactoryProtocol = SR25519KeypairFactory()

    // cache public key to access secrets only once to get it
    private var publicKey: IRPublicKeyProtocol?
    private let mutex = NSLock()

    public init(derivationPath: String?, entropyManager: RootEntropyManaging) {
        self.derivationPath = derivationPath
        mnemonicProvider = WalletKeystoreMnemonicProvider(entropyManager: entropyManager)
    }

    public init(mnemonic: String, derivationPath: String?) {
        self.derivationPath = derivationPath
        mnemonicProvider = WalletMnemonicProvider(mnemonic: mnemonic)
    }
}

private extension WalletMnemonicKeypairFactory {
    func performKeypairDerivation() throws -> IRCryptoKeypairProtocol {
        let mnemonic = try mnemonicProvider.fetchMnemonic()

        if let derivationPath {
            let junctionResult = try junctionFactory.parse(path: derivationPath)
            let password = junctionResult.password ?? ""
            let chaincodes = junctionResult.chaincodes

            let seedResult = try seedFactory.deriveSeed(from: mnemonic, password: password)

            let keypair = try keypairFactory.createKeypairFromSeed(
                seedResult.seed.miniSeed,
                chaincodeList: chaincodes
            )

            publicKey = keypair.publicKey()

            return keypair
        } else {
            let seedResult = try seedFactory.deriveSeed(
                from: mnemonic,
                password: ""
            )

            let keypair = try keypairFactory.createKeypairFromSeed(
                seedResult.seed.miniSeed,
                chaincodeList: []
            )

            publicKey = keypair.publicKey()

            return keypair
        }
    }
}

extension WalletMnemonicKeypairFactory: WalletKeypairFactoryProtocol {
    public func deriveKeypair() throws -> IRCryptoKeypairProtocol {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        return try performKeypairDerivation()
    }

    public func derivePublicKey() throws -> IRPublicKeyProtocol {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let publicKey {
            return publicKey
        }

        return try performKeypairDerivation().publicKey()
    }
}

extension WalletMnemonicKeypairFactory: SigningSecretProviding {
    public func fetchSignerSecret(for _: SignerProviding) throws -> Data {
        try deriveKeypair().privateKey().rawData()
    }
}
