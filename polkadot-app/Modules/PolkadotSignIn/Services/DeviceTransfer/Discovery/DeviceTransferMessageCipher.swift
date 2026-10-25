import Foundation
import MessageExchangeKit
import SubstrateSdkExt

/// Seals discovery messages under `HKDF-SHA256(k_req)`, the derivation the transfer session uses for `k_s`.
struct DeviceTransferMessageCipher {
    private let encryptor: ChaChaPolyEncryptor

    init(requestKey: Data) {
        encryptor = ChaChaPolyEncryptor(presharedKey: requestKey)
    }

    func seal(_ message: DeviceTransferMessage) throws -> Data {
        try encryptor.encrypt(message.scaleEncoded())
    }

    func open(_ sealed: Data) throws -> DeviceTransferMessage {
        try DeviceTransferMessage.fromScaleEncoded(encryptor.decrypt(sealed))
    }
}
