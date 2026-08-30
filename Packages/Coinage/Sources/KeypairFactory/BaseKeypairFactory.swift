import KeyDerivation

/// A protocol for models that can be derived using an index.
public protocol CoinageDerivable {
    var derivationIndex: DerivationIndex { get }
}

public protocol CoinageKeypairFactory {
    associatedtype Model: CoinageDerivable

    /// Derives the public key for a derivation index.
    func derivePublicKey(index: DerivationIndex) throws -> PublicKey

    /// Derives the private key for a derivation index.
    func derivePrivateKey(index: DerivationIndex) throws -> PrivateKey
}

public extension CoinageKeypairFactory {
    /// Derives the private key for a model from its derivation index. Public keys are read from the
    /// model directly (``CoinageDerivable`` carries a cached one), so there is no model-based public
    /// key derivation here.
    func derivePrivateKey(for model: Model) throws -> PrivateKey {
        try derivePrivateKey(index: model.derivationIndex)
    }
}

/// A generic base class to handle shared derivation logic.
public class BaseKeypairFactory<Model: CoinageDerivable>: CoinageKeypairFactory {
    private let basePath: String
    public let entropyManager: RootEntropyManaging

    public init(
        basePath: String,
        entropyManager: RootEntropyManaging
    ) {
        self.basePath = basePath
        self.entropyManager = entropyManager
    }

    public func derivePublicKey(index _: DerivationIndex) throws -> PublicKey {
        fatalError("Override in subclass")
    }

    public func derivePrivateKey(index _: DerivationIndex) throws -> PrivateKey {
        fatalError("Override in subclass")
    }
}

public extension BaseKeypairFactory {
    func derivationPath(index: DerivationIndex) -> String {
        "\(basePath)//\(index)"
    }
}
