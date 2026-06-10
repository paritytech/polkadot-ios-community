import KeyDerivation
import SubstrateSdk
import NovaCrypto

protocol CoinKeyDeriving: CoinageKeypairFactory where Model == Coin {}

extension CoinKeyDeriving {
    func derivePublicKey(placeholderIndex index: UInt32) throws -> PublicKey {
        let placeholder = Coin(exponent: 0, derivationIndex: index, age: nil)
        return try derivePublicKey(for: placeholder)
    }
}

final class CoinKeypairFactory: BaseKeypairFactory<Coin>, CoinKeyDeriving {
    init(entropyManager: RootEntropyManaging) {
        super.init(basePath: "//pps//coin", entropyManager: entropyManager)
    }

    override func derivePublicKey(for model: Coin) throws -> PublicKey {
        let path = derivationPath(for: model)
        return try WalletMnemonicKeypairFactory(
            derivationPath: path,
            entropyManager: entropyManager
        )
        .derivePublicKey()
        .rawData()
    }

    override func derivePrivateKey(for model: Coin) throws -> PrivateKey {
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
