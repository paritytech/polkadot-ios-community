import KeyDerivation
import SubstrateSdk
import NovaCrypto

public protocol CoinKeyDeriving: CoinageKeypairFactory where Model == Coin {}

public final class CoinKeypairFactory: BaseKeypairFactory<Coin>, CoinKeyDeriving {
    public init(entropyManager: RootEntropyManaging) {
        super.init(basePath: "//pps//coin", entropyManager: entropyManager)
    }

    override public func derivePublicKey(index: DerivationIndex) throws -> PublicKey {
        try WalletMnemonicKeypairFactory(
            derivationPath: derivationPath(index: index),
            entropyManager: entropyManager
        )
        .derivePublicKey()
        .rawData()
    }

    override public func derivePrivateKey(index: DerivationIndex) throws -> PrivateKey {
        try WalletMnemonicKeypairFactory(
            derivationPath: derivationPath(index: index),
            entropyManager: entropyManager
        )
        .deriveKeypair()
        .privateKey()
        .rawData()
    }
}
