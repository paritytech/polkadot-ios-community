import Coinage
import Foundation
import SubstrateSdk

// MARK: - Model

extension Chat {
    /// A coin this user handed off, given by its derivation so the receiving device can rebuild it from the seed.
    struct DeviceSyncHandedOffCoin: Equatable {
        static let installationIdLength = CoinageInstallationId.sizeBytes

        let installationId: Data
        let derivationIndex: UInt64
        let exponent: Int16
    }

    enum DeviceSyncCoinageMessageStatus: Equatable {
        case none
        /// `partial` is below the message total when only part of it was claimed.
        case claimed(partial: Balance?)
        case failed
    }

    /// Carried by `coinageMessagesStatusUpdated` (incoming claims) and `outgoingTransferStatesUpdated`.
    struct DeviceSyncCoinageMessageStatusUpdate: Equatable {
        let chatId: DeviceSyncChatId
        let messageId: String
        let status: DeviceSyncCoinageMessageStatus
    }

    /// A status update with the direction its entity gave it, kept while its message hasn't arrived.
    enum DeviceSyncTransferStateUpdate: Equatable {
        case incoming(DeviceSyncCoinageMessageStatusUpdate)
        case outgoing(DeviceSyncCoinageMessageStatusUpdate)

        var update: DeviceSyncCoinageMessageStatusUpdate {
            switch self {
            case let .incoming(update),
                 let .outgoing(update): update
            }
        }

        var messageId: String { update.messageId }
    }
}

// MARK: - ScaleCodable

extension Chat.DeviceSyncHandedOffCoin: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        installationId = try scaleDecoder.readAndConfirm(count: Self.installationIdLength)
        derivationIndex = try UInt64(scaleDecoder: scaleDecoder)
        exponent = try Int16(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        scaleEncoder.appendRaw(data: installationId)
        try derivationIndex.encode(scaleEncoder: scaleEncoder)
        try exponent.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncCoinageMessageStatus: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        switch try UInt8(scaleDecoder: scaleDecoder) {
        case 0:
            self = .none
        case 1:
            self = try .claimed(partial: ScaleOption<Balance>(scaleDecoder: scaleDecoder).value)
        case 2:
            self = .failed
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case .none:
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
        case let .claimed(partial):
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
            try ScaleOption(value: partial).encode(scaleEncoder: scaleEncoder)
        case .failed:
            try UInt8(2).encode(scaleEncoder: scaleEncoder)
        }
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
