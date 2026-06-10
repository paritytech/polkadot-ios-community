import Foundation
import Keystore_iOS
import NovaCrypto
import SubstrateSdk
import CryptoKit
import MessageExchangeKit
import KeyDerivation

protocol ChatPrivateKeyMaking {
    func derivePrivateKey() throws -> P256.KeyAgreement.PrivateKey
}

final class ChatPrivateKeyFactory {
    private let derivationPath: String
    private let entropyManager: RootEntropyManaging
    private let mnemonicGenerator: IRMnemonicCreatorProtocol
    private let junctionFactory: JunctionFactoryProtocol
    private let seedFactory: SeedFactoryProtocol
    private let keypairFactory: KeypairFactoryProtocol

    init(
        derivationPath: String,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared,
        mnemonicGenerator: IRMnemonicCreatorProtocol = IRMnemonicCreator(),
        junctionFactory: JunctionFactoryProtocol = SubstrateJunctionFactory(),
        seedFactory: SeedFactoryProtocol = SeedFactory(),
        keypairFactory: KeypairFactoryProtocol = SR25519KeypairFactory()
    ) {
        self.derivationPath = derivationPath
        self.entropyManager = entropyManager
        self.mnemonicGenerator = mnemonicGenerator
        self.junctionFactory = junctionFactory
        self.seedFactory = seedFactory
        self.keypairFactory = keypairFactory
    }
}

extension ChatPrivateKeyFactory: ChatPrivateKeyMaking {
    func derivePrivateKey() throws -> P256.KeyAgreement.PrivateKey {
        let entropy = try entropyManager.fetchRootEntropy()
        let mnemonic = try mnemonicGenerator.mnemonic(fromEntropy: entropy)

        let junctionResult = try junctionFactory.parse(path: derivationPath)
        let password = junctionResult.password ?? ""
        let chaincodes = junctionResult.chaincodes

        let seedResult = try seedFactory.deriveSeed(
            from: mnemonic.toString(),
            password: password
        )

        let substrateKeypair = try keypairFactory.createKeypairFromSeed(
            seedResult.seed.miniSeed,
            chaincodeList: chaincodes
        )

        let privateKey = try P256.KeyAgreement.PrivateKey(
            rawRepresentation: substrateKeypair.privateKey().rawData().prefix(32).blake2b32()
        )

        return privateKey
    }
}

enum ChatDerivationPath: String {
    case mainChat = "//wallet//chat"
    case sso = "//wallet//sso"
    case gameChat = "//candidate//popCandidate"
}
