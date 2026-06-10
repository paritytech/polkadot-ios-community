import Foundation
import CryptoKit

public protocol MessageExchangeEncryptionManaging {
    func makeEncryptorFactory(ownEncryptionKeyId: String) throws -> MessageExchangeEncryptionMaking
}

public class ClosureEncryptionManager: MessageExchangeEncryptionManaging {
    private let closure: (String) throws -> MessageExchangeEncryptionMaking

    public init(closure: @escaping (String) throws -> MessageExchangeEncryptionMaking) {
        self.closure = closure
    }

    public func makeEncryptorFactory(ownEncryptionKeyId: String) throws -> MessageExchangeEncryptionMaking {
        try closure(ownEncryptionKeyId)
    }
}

public protocol MessageExchangeEncryptionMaking {
    var localPublicKey: Data { get }
    var localPrivateKey: Data { get }

    func makeEncryptor(remotePublicKey: Data) throws -> MessageExchangeEncrypting
}

public final class P256AESEncryptorFactory: MessageExchangeEncryptionMaking {
    private let privateKey: P256.KeyAgreement.PrivateKey

    public init(privateKey: P256.KeyAgreement.PrivateKey) {
        self.privateKey = privateKey
    }

    public var localPublicKey: Data {
        privateKey.publicKey.x963Representation
    }

    public var localPrivateKey: Data {
        privateKey.rawRepresentation
    }

    public func makeEncryptor(remotePublicKey: Data) throws -> MessageExchangeEncrypting {
        let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: remotePublicKey)
        let sharedKey = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return AESEncryptor(sharedSecret: sharedKey)
    }
}
