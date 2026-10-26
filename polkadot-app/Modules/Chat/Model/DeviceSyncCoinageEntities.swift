import Foundation
import SubstrateSdk

// MARK: - Model

extension Chat {
    /// A coin this user handed off, given by its derivation so the receiving device can rebuild it from the seed.
    struct DeviceSyncHandedOffCoin: Equatable {
        static let installationIdLength = 32

        let installationId: Data
        let derivationIndex: UInt64
        let exponent: Int16
        let age: Int16?
    }

    enum DeviceSyncCoinageMessageStatus: UInt8, Equatable {
        case none = 0
        case claimed = 1
        case failed = 2
    }

    /// `claimedValue` is set for a claim, and is below the message total for a partial one.
    struct DeviceSyncCoinageMessageStatusUpdate: Equatable {
        let chatId: DeviceSyncChatId
        let messageId: String
        let status: DeviceSyncCoinageMessageStatus
        let claimedValue: Balance?
    }
}

// MARK: - ScaleCodable

extension Chat.DeviceSyncHandedOffCoin: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        installationId = try scaleDecoder.readAndConfirm(count: Self.installationIdLength)
        derivationIndex = try UInt64(scaleDecoder: scaleDecoder)
        exponent = try Int16(scaleDecoder: scaleDecoder)
        age = try ScaleOption<Int16>(scaleDecoder: scaleDecoder).value
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        scaleEncoder.appendRaw(data: installationId)
        try derivationIndex.encode(scaleEncoder: scaleEncoder)
        try exponent.encode(scaleEncoder: scaleEncoder)
        try ScaleOption(value: age).encode(scaleEncoder: scaleEncoder)
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
        claimedValue = try ScaleOption<Balance>(scaleDecoder: scaleDecoder).value
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try chatId.encode(scaleEncoder: scaleEncoder)
        try messageId.encode(scaleEncoder: scaleEncoder)
        try status.encode(scaleEncoder: scaleEncoder)
        try ScaleOption(value: claimedValue).encode(scaleEncoder: scaleEncoder)
    }
}
