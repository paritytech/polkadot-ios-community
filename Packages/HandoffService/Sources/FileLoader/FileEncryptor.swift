import Foundation
import CryptoKit

public protocol FileEncrypting {
    func encrypt(_ data: Data) throws -> Data
    func decrypt(_ encryptedData: Data) throws -> Data
}

public enum AESFileEncryptorError: Error {
    case missingCipher
}

public final class AESFileEncryptor {
    let symmetricKey: SymmetricKey

    public init(rawKey: Data) {
        symmetricKey = SymmetricKey(data: rawKey)
    }

    public init(symmetricKey: SymmetricKey) {
        self.symmetricKey = symmetricKey
    }
}

extension AESFileEncryptor: FileEncrypting {
    public func encrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: symmetricKey) // default nonce = 12, tag = 16

        guard let combined = box.combined else {
            throw AESFileEncryptorError.missingCipher
        }

        return combined
    }

    public func decrypt(_ encryptedData: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: encryptedData) // default nonce = 12, tag = 16
        return try AES.GCM.open(box, using: symmetricKey)
    }
}
