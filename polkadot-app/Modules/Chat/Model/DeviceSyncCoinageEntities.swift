import Foundation
import SubstrateSdk

// MARK: - Model

extension Chat {
    /// A coin's 32-byte public key, encoded without a length prefix.
    struct DeviceSyncCoinKey: Equatable {
        static let length = 32

        let publicKey: Data
    }

    enum DeviceSyncCoinageMessageStatus: UInt8, Equatable {
        case none = 0
        case claimed = 1
        case failed = 2
    }

    struct DeviceSyncCoinageMessageStatusUpdate: Equatable {
        let chatId: DeviceSyncChatId
        let messageId: String
        let status: DeviceSyncCoinageMessageStatus
    }
}

// MARK: - ScaleCodable

extension Chat.DeviceSyncCoinKey: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        publicKey = try scaleDecoder.readAndConfirm(count: Self.length)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        scaleEncoder.appendRaw(data: publicKey)
    }
}

extension Chat.DeviceSyncCoinageMessageStatus: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        guard let status = try Self(rawValue: UInt8(scaleDecoder: scaleDecoder)) else {
            throw ScaleCodingError.unexpectedDecodedValue
        }
        self = status
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try rawValue.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncCoinageMessageStatusUpdate: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        chatId = try Chat.DeviceSyncChatId(scaleDecoder: scaleDecoder)
        messageId = try String(scaleDecoder: scaleDecoder)
        status = try Chat.DeviceSyncCoinageMessageStatus(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try chatId.encode(scaleEncoder: scaleEncoder)
        try messageId.encode(scaleEncoder: scaleEncoder)
        try status.encode(scaleEncoder: scaleEncoder)
    }
}
