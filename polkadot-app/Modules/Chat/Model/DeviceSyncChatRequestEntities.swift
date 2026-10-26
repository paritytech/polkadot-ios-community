import Foundation
import SubstrateSdk

// MARK: - Model

extension Chat {
    struct DeviceSyncChatBlockState: Equatable {
        let chatId: DeviceSyncChatId
        let blocked: Bool
    }

    enum DeviceSyncIncomingRequestStatus: UInt8, Equatable {
        case pending = 0
        case accepted = 1
        case declined = 2
    }

    /// `requestId` is the request message's `messageId`; `peer` is the requester's identity account.
    struct DeviceSyncIncomingChatRequest: Equatable {
        let requestId: String
        let peer: Data
        let timestamp: UInt64
        let status: DeviceSyncIncomingRequestStatus
        let peerDevice: DeviceSyncWireDevice?
        let pushToken: RemoteTokenContent?
        let welcomeMessage: ChatRemoteMessageContent.RichText?
    }

    struct DeviceSyncIncomingRequestStatusUpdate: Equatable {
        let requestId: String
        let status: DeviceSyncIncomingRequestStatus
    }

    enum DeviceSyncOutgoingRequestStatus: UInt8, Equatable {
        case pending = 0
        case accepted = 1
        case cancelled = 2
    }

    /// `requestId` is the request message's `messageId`; `peer` is the acceptor's identity account. `content` is the
    /// stored request, so the receiving device republishes the same bytes.
    struct DeviceSyncOutgoingChatRequest: Equatable {
        let requestId: String
        let peer: Data
        let timestamp: UInt64
        let status: DeviceSyncOutgoingRequestStatus
        let content: VersionedRequestContent
    }

    struct DeviceSyncOutgoingRequestStatusUpdate: Equatable {
        let requestId: String
        let status: DeviceSyncOutgoingRequestStatus
    }
}

// MARK: - ScaleCodable

extension Chat.DeviceSyncChatBlockState: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        chatId = try Chat.DeviceSyncChatId(scaleDecoder: scaleDecoder)
        blocked = try Bool(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try chatId.encode(scaleEncoder: scaleEncoder)
        try blocked.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncIncomingRequestStatus: ScaleCodable {
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

extension Chat.DeviceSyncIncomingChatRequest: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try String(scaleDecoder: scaleDecoder)
        peer = try scaleDecoder.readAndConfirm(count: Chat.DeviceSyncWireMessage.peerIdLength)
        timestamp = try UInt64(scaleDecoder: scaleDecoder)
        status = try Chat.DeviceSyncIncomingRequestStatus(scaleDecoder: scaleDecoder)
        peerDevice = try ScaleOption<Chat.DeviceSyncWireDevice>(scaleDecoder: scaleDecoder).value
        pushToken = try ScaleOption<Chat.RemoteTokenContent>(scaleDecoder: scaleDecoder).value
        welcomeMessage = try ScaleOption<ChatRemoteMessageContent.RichText>(scaleDecoder: scaleDecoder).value
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        scaleEncoder.appendRaw(data: peer)
        try timestamp.encode(scaleEncoder: scaleEncoder)
        try status.encode(scaleEncoder: scaleEncoder)
        try ScaleOption(value: peerDevice).encode(scaleEncoder: scaleEncoder)
        try ScaleOption(value: pushToken).encode(scaleEncoder: scaleEncoder)
        try ScaleOption(value: welcomeMessage).encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncIncomingRequestStatusUpdate: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try String(scaleDecoder: scaleDecoder)
        status = try Chat.DeviceSyncIncomingRequestStatus(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try status.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncOutgoingRequestStatus: ScaleCodable {
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

extension Chat.DeviceSyncOutgoingChatRequest: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try String(scaleDecoder: scaleDecoder)
        peer = try scaleDecoder.readAndConfirm(count: Chat.DeviceSyncWireMessage.peerIdLength)
        timestamp = try UInt64(scaleDecoder: scaleDecoder)
        status = try Chat.DeviceSyncOutgoingRequestStatus(scaleDecoder: scaleDecoder)
        content = try Chat.VersionedRequestContent(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        scaleEncoder.appendRaw(data: peer)
        try timestamp.encode(scaleEncoder: scaleEncoder)
        try status.encode(scaleEncoder: scaleEncoder)
        try content.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncOutgoingRequestStatusUpdate: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try String(scaleDecoder: scaleDecoder)
        status = try Chat.DeviceSyncOutgoingRequestStatus(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try status.encode(scaleEncoder: scaleEncoder)
    }
}
