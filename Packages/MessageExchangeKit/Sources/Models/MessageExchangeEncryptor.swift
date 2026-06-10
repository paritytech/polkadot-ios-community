import Foundation
import CryptoKit

public protocol MessageExchangeEncrypting {
    var sharedSecret: Data { get }

    func encrypt(_ message: Data) throws -> Data
    func decrypt(_ message: Data) throws -> Data
}

enum MessageExchangeEncryptionError: Error {
    case missingCombinedData
}

public final class AESEncryptor {
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

extension AESEncryptor: MessageExchangeEncrypting {
    public var sharedSecret: Data {
        internalSharedSecret.withUnsafeBytes { Data($0) }
    }

    public func encrypt(_ message: Data) throws -> Data {
        let box = try AES.GCM.seal(message, using: internalSymmetricKey) // default nonce = 12, tag = 16

        guard let combined = box.combined else {
            throw MessageExchangeEncryptionError.missingCombinedData
        }

        return combined
    }

    public func decrypt(_ message: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: message) // default nonce = 12, tag = 16
        return try AES.GCM.open(box, using: internalSymmetricKey)
    }
}
