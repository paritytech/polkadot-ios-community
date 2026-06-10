import Foundation
import CryptoKit
import MessageExchangeKit

final class DeviceSyncEncryptionManager {
    private let privateKey: P256.KeyAgreement.PrivateKey

    init(privateKey: P256.KeyAgreement.PrivateKey) {
        self.privateKey = privateKey
    }
}

extension DeviceSyncEncryptionManager: MessageExchangeEncryptionManaging {
    func makeEncryptorFactory(
        ownEncryptionKeyId _: String
    ) throws -> MessageExchangeEncryptionMaking {
        P256AESEncryptorFactory(privateKey: privateKey)
    }
}
