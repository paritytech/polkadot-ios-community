import Foundation
import CryptoKit

public protocol MessageExchangeEncrypting {
    var sharedSecret: Data { get }

    func encrypt(_ message: Data) throws -> Data
    func decrypt(_ message: Data) throws -> Data
}

public final class ECDHChaChaPolyEncryptor {
    private let internalSharedSecret: SharedSecret
    private let internalSymmetricKey: SymmetricKey

    public init(sharedSecret: SharedSecret) {
        internalSharedSecret = sharedSecret
        internalSymmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }
}

extension ECDHChaChaPolyEncryptor: MessageExchangeEncrypting {
    public var sharedSecret: Data {
        internalSharedSecret.withUnsafeBytes { Data($0) }
    }

    public func encrypt(_ message: Data) throws -> Data {
        try ChaChaPolySealing.seal(message, using: internalSymmetricKey)
    }

    public func decrypt(_ message: Data) throws -> Data {
        try ChaChaPolySealing.open(message, using: internalSymmetricKey)
    }
}

/// For a secret both sides already hold instead of an X25519 agreement; the key is derived with the same HKDF.
public final class RawSecretChaChaPolyEncryptor {
    public let sharedSecret: Data
    private let internalSymmetricKey: SymmetricKey

    public init(sharedSecret: Data) {
        self.sharedSecret = sharedSecret
        internalSymmetricKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sharedSecret),
            salt: Data(),
            info: Data(),
            outputByteCount: 32
        )
    }
}

extension RawSecretChaChaPolyEncryptor: MessageExchangeEncrypting {
    public func encrypt(_ message: Data) throws -> Data {
        try ChaChaPolySealing.seal(message, using: internalSymmetricKey)
    }

    public func decrypt(_ message: Data) throws -> Data {
        try ChaChaPolySealing.open(message, using: internalSymmetricKey)
    }
}

private enum ChaChaPolySealing {
    static func seal(_ message: Data, using key: SymmetricKey) throws -> Data {
        try ChaChaPoly.seal(message, using: key).combined // nonce = 12, tag = 16
    }

    static func open(_ message: Data, using key: SymmetricKey) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: message) // nonce = 12, tag = 16
        return try ChaChaPoly.open(box, using: key)
    }
}
