import KeyDerivation

/// A protocol for models that can be derived using an index.
public protocol CoinageDerivable {
    var derivationIndex: UInt32 { get }
}

public protocol CoinageKeypairFactory {
    associatedtype Model: CoinageDerivable

    /// Derives the public key
    func derivePublicKey(for model: Model) throws -> PublicKey

    /// Derives the private key
    func derivePrivateKey(for model: Model) throws -> PrivateKey
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

    public func derivePublicKey(for _: Model) throws -> PublicKey {
        fatalError("Override in subclass")
    }

    public func derivePrivateKey(for _: Model) throws -> PrivateKey {
        fatalError("Override in subclass")
    }
}

public extension BaseKeypairFactory {
    func derivationPath(for model: Model) -> String {
        "\(basePath)//\(model.derivationIndex)"
    }
}
