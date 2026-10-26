import Foundation
import MessageExchangeKit

/// Encrypts a device transfer session with `k_s`, which both phones derive from the same entropy, so no key
/// agreement takes place and the peer's public key is ignored.
final class PresharedKeyEncryptionManager {
    private let presharedKey: Data

    init(presharedKey: Data) {
        self.presharedKey = presharedKey
    }
}

extension PresharedKeyEncryptionManager: MessageExchangeEncryptionManaging, MessageExchangeEncryptionMaking {
    var localPublicKey: Data { Data() }
    var localPrivateKey: Data { Data() }

    func makeEncryptorFactory(ownEncryptionKeyId _: String) throws -> MessageExchangeEncryptionMaking {
        self
    }

    func makeEncryptor(remotePublicKey _: Data) throws -> MessageExchangeEncrypting {
        ChaChaPolyEncryptor(presharedKey: presharedKey)
    }
}
