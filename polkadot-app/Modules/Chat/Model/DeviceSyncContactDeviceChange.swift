import Foundation
import SubstrateSdk

extension Chat {
    /// A contact's device as last changed by the peer; `changedAt` is the peer's event time in milliseconds.
    struct DeviceSyncContactDeviceChange: Equatable {
        let chatId: DeviceSyncChatId
        let device: PeerDevice
        let status: ContactDeviceStatus
        let changedAt: UInt64
    }
}

// MARK: - ScaleCodable

extension Chat.DeviceSyncContactDeviceChange: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        chatId = try Chat.DeviceSyncChatId(scaleDecoder: scaleDecoder)
        device = try Chat.PeerDevice(
            statementAccountId: scaleDecoder.readAndConfirm(count: 32),
            encryptionPublicKey: scaleDecoder.readAndConfirm(count: 32)
        )

        let rawStatus = try UInt8(scaleDecoder: scaleDecoder)
        guard let status = Chat.ContactDeviceStatus(rawValue: Int16(rawStatus)) else {
            throw ScaleCodingError.unexpectedDecodedValue
        }
        self.status = status

        changedAt = try UInt64(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try chatId.encode(scaleEncoder: scaleEncoder)
        scaleEncoder.appendRaw(data: device.statementAccountId)
        scaleEncoder.appendRaw(data: device.encryptionPublicKey)
        try UInt8(status.rawValue).encode(scaleEncoder: scaleEncoder)
        try changedAt.encode(scaleEncoder: scaleEncoder)
    }
}
