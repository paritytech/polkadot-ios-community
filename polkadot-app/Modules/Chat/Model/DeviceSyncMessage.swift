import Foundation
import SubstrateSdk

// MARK: - Model

extension Chat {
    enum DeviceSyncEntity: Equatable {
        case devices([DeviceSyncWireDevice])
        case chatsAdded([DeviceSyncChatId])
        case chatsRemoved([DeviceSyncChatId])
        case messages([DeviceSyncWireMessage])
        case chatsBlocked([DeviceSyncChatBlockState])
        case incomingRequestsAdded([DeviceSyncIncomingChatRequest])
        case incomingRequestsStatusUpdated([DeviceSyncIncomingRequestStatusUpdate])
        case outgoingRequestsAdded([DeviceSyncOutgoingChatRequest])
        case outgoingRequestsStatusUpdated([DeviceSyncOutgoingRequestStatusUpdate])
        case coinsHandedOff([DeviceSyncCoinKey])
        case coinageMessagesStatusUpdated([DeviceSyncCoinageMessageStatusUpdate])

        var logLabel: String {
            switch self {
            case .devices: "devices"
            case .chatsAdded: "chatsAdded"
            case .chatsRemoved: "chatsRemoved"
            case .messages: "messages"
            case .chatsBlocked: "chatsBlocked"
            case .incomingRequestsAdded: "incomingRequestsAdded"
            case .incomingRequestsStatusUpdated: "incomingRequestsStatusUpdated"
            case .outgoingRequestsAdded: "outgoingRequestsAdded"
            case .outgoingRequestsStatusUpdated: "outgoingRequestsStatusUpdated"
            case .coinsHandedOff: "coinsHandedOff"
            case .coinageMessagesStatusUpdated: "coinageMessagesStatusUpdated"
            }
        }
    }

    struct DeviceSyncUpdate: Equatable {
        let id: UInt32
        let entities: [DeviceSyncEntity]
        let timePoint: UInt64
    }

    struct DeviceSyncUpdateAck: Equatable {
        let id: UInt32
    }

    enum DeviceSyncMessage: Equatable {
        case update(DeviceSyncUpdate)
        case ack(DeviceSyncUpdateAck)
    }
}

// MARK: - ScaleCodable: DeviceSyncEntity

extension Chat.DeviceSyncEntity: ScaleCodable {
    // swiftlint:disable:next cyclomatic_complexity
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = try .devices([Chat.DeviceSyncWireDevice](scaleDecoder: scaleDecoder))
        case 1:
            self = try .chatsAdded([Chat.DeviceSyncChatId](scaleDecoder: scaleDecoder))
        case 2:
            self = try .chatsRemoved([Chat.DeviceSyncChatId](scaleDecoder: scaleDecoder))
        case 3:
            self = try .messages([Chat.DeviceSyncWireMessage](scaleDecoder: scaleDecoder))
        case 4:
            self = try .chatsBlocked([Chat.DeviceSyncChatBlockState](scaleDecoder: scaleDecoder))
        case 5:
            self = try .incomingRequestsAdded([Chat.DeviceSyncIncomingChatRequest](scaleDecoder: scaleDecoder))
        case 6:
            self = try .incomingRequestsStatusUpdated(
                [Chat.DeviceSyncIncomingRequestStatusUpdate](scaleDecoder: scaleDecoder)
            )
        case 7:
            self = try .outgoingRequestsAdded([Chat.DeviceSyncOutgoingChatRequest](scaleDecoder: scaleDecoder))
        case 8:
            self = try .outgoingRequestsStatusUpdated(
                [Chat.DeviceSyncOutgoingRequestStatusUpdate](scaleDecoder: scaleDecoder)
            )
        case 9:
            self = try .coinsHandedOff([Chat.DeviceSyncCoinKey](scaleDecoder: scaleDecoder))
        case 10:
            self = try .coinageMessagesStatusUpdated(
                [Chat.DeviceSyncCoinageMessageStatusUpdate](scaleDecoder: scaleDecoder)
            )
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .devices(devices):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            try devices.encode(scaleEncoder: scaleEncoder)
        case let .chatsAdded(chatIds):
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
            try chatIds.encode(scaleEncoder: scaleEncoder)
        case let .chatsRemoved(chatIds):
            try UInt8(2).encode(scaleEncoder: scaleEncoder)
            try chatIds.encode(scaleEncoder: scaleEncoder)
        case let .messages(messages):
            try UInt8(3).encode(scaleEncoder: scaleEncoder)
            try messages.encode(scaleEncoder: scaleEncoder)
        case let .chatsBlocked(states):
            try UInt8(4).encode(scaleEncoder: scaleEncoder)
            try states.encode(scaleEncoder: scaleEncoder)
        case let .incomingRequestsAdded(requests):
            try UInt8(5).encode(scaleEncoder: scaleEncoder)
            try requests.encode(scaleEncoder: scaleEncoder)
        case let .incomingRequestsStatusUpdated(updates):
            try UInt8(6).encode(scaleEncoder: scaleEncoder)
            try updates.encode(scaleEncoder: scaleEncoder)
        case let .outgoingRequestsAdded(requests):
            try UInt8(7).encode(scaleEncoder: scaleEncoder)
            try requests.encode(scaleEncoder: scaleEncoder)
        case let .outgoingRequestsStatusUpdated(updates):
            try UInt8(8).encode(scaleEncoder: scaleEncoder)
            try updates.encode(scaleEncoder: scaleEncoder)
        case let .coinsHandedOff(keys):
            try UInt8(9).encode(scaleEncoder: scaleEncoder)
            try keys.encode(scaleEncoder: scaleEncoder)
        case let .coinageMessagesStatusUpdated(updates):
            try UInt8(10).encode(scaleEncoder: scaleEncoder)
            try updates.encode(scaleEncoder: scaleEncoder)
        }
    }
}

// MARK: - ScaleCodable: DeviceSyncUpdate & DeviceSyncUpdateAck

extension Chat.DeviceSyncUpdate: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        id = try UInt32(scaleDecoder: scaleDecoder)
        entities = try [Chat.DeviceSyncEntity](scaleDecoder: scaleDecoder)
        timePoint = try UInt64(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try id.encode(scaleEncoder: scaleEncoder)
        try entities.encode(scaleEncoder: scaleEncoder)
        try timePoint.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncUpdateAck: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        id = try UInt32(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try id.encode(scaleEncoder: scaleEncoder)
    }
}

// MARK: - ScaleCodable: DeviceSyncMessage

extension Chat.DeviceSyncMessage: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = try .update(Chat.DeviceSyncUpdate(scaleDecoder: scaleDecoder))
        case 1:
            self = try .ack(Chat.DeviceSyncUpdateAck(scaleDecoder: scaleDecoder))
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .update(update):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            try update.encode(scaleEncoder: scaleEncoder)
        case let .ack(ack):
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
            try ack.encode(scaleEncoder: scaleEncoder)
        }
    }
}
