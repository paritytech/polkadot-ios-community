import KeyDerivation
import SubstrateSdk
import NovaCrypto

public protocol CoinKeyDeriving: CoinageKeypairFactory where Model == Coin {}

public extension CoinKeyDeriving {
    func derivePublicKey(placeholderIndex index: DerivationIndex) throws -> PublicKey {
        let placeholder = Coin(exponent: 0, derivationIndex: index, age: nil)
        return try derivePublicKey(for: placeholder)
    }
}

public final class CoinKeypairFactory: BaseKeypairFactory<Coin>, CoinKeyDeriving {
    public init(entropyManager: RootEntropyManaging) {
        super.init(basePath: "//pps//coin", entropyManager: entropyManager)
    }

    override public func derivePublicKey(for model: Coin) throws -> PublicKey {
        let path = derivationPath(for: model)
        return try WalletMnemonicKeypairFactory(
            derivationPath: path,
            entropyManager: entropyManager
        )
        .derivePublicKey()
        .rawData()
    }

    override public func derivePrivateKey(for model: Coin) throws -> PrivateKey {
        let path = derivationPath(for: model)
        return try WalletMnemonicKeypairFactory(
            derivationPath: path,
            entropyManager: entropyManager
        )
        .deriveKeypair()
        .privateKey()
        .rawData()
    }
}
