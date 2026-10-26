import Foundation
import CryptoKit

public protocol MessageExchangeEncrypting {
    var sharedSecret: Data { get }

    func encrypt(_ message: Data) throws -> Data
    func decrypt(_ message: Data) throws -> Data
}

public final class ChaChaPolyEncryptor {
    public let sharedSecret: Data
    private let internalSymmetricKey: SymmetricKey

    public convenience init(sharedSecret: SharedSecret) {
        self.init(presharedKey: sharedSecret.withUnsafeBytes { Data($0) })
    }

    /// For sessions keyed by a secret both sides already hold instead of an X25519 agreement. The cipher key is
    /// derived with the same HKDF as for an agreed `SharedSecret`.
    public init(presharedKey: Data) {
        sharedSecret = presharedKey
        internalSymmetricKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: presharedKey),
            salt: Data(),
            info: Data(),
            outputByteCount: 32
        )
    }
}

extension ChaChaPolyEncryptor: MessageExchangeEncrypting {
    public func encrypt(_ message: Data) throws -> Data {
        try ChaChaPoly.seal(message, using: internalSymmetricKey).combined // nonce = 12, tag = 16
    }

    public func decrypt(_ message: Data) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: message) // nonce = 12, tag = 16
        return try ChaChaPoly.open(box, using: internalSymmetricKey)
    }
}
