import Foundation
import SubstrateSdk

// MARK: - Model

extension Chat {
    /// Payload of the `device-sync-file` data channel use case (File Transfer RFC).
    enum DeviceSyncFileMessage: Equatable {
        case filesRequest(Request)
        case header(Header)
        case chunk(Chunk)
        case unavailable(Unavailable)
        case cancelFilesRequest(requestId: UInt32)
        case completed(requestId: UInt32)
        case availabilityRequest(AvailabilityRequest)
        case availabilityResponse(AvailabilityResponse)
    }
}

extension Chat.DeviceSyncFileMessage {
    struct MessageAttachmentId: Hashable {
        let messageId: Chat.MessageId
        let identifier: Data
    }

    enum FileReference: Hashable {
        case messageAttachment(MessageAttachmentId)
    }

    struct RequestItem: Equatable {
        let file: FileReference
        let offset: UInt64
    }

    struct Request: Equatable {
        let requestId: UInt32
        let files: [RequestItem]
    }

    struct Header: Equatable {
        let requestId: UInt32
        let fileIndex: UInt32
        let totalSize: UInt64
    }

    struct Chunk: Equatable {
        let requestId: UInt32
        let fileIndex: UInt32
        let offset: UInt64
        let data: Data
    }

    enum UnavailableReason: UInt8, Equatable {
        case notStored = 0
        case downloading = 1
    }

    struct Unavailable: Equatable {
        let requestId: UInt32
        let fileIndex: UInt32
        let reason: UnavailableReason
    }

    struct AvailabilityRequest: Equatable {
        let requestId: UInt32
        let files: [FileReference]
    }

    enum Availability: Equatable {
        case available(totalSize: UInt64)
        case unavailable(UnavailableReason)
    }

    struct AvailabilityResponse: Equatable {
        let requestId: UInt32
        let availability: [Availability]
    }
}

// MARK: - ScaleCodable: DeviceSyncFileMessage

extension Chat.DeviceSyncFileMessage: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = try .filesRequest(Request(scaleDecoder: scaleDecoder))
        case 1:
            self = try .header(Header(scaleDecoder: scaleDecoder))
        case 2:
            self = try .chunk(Chunk(scaleDecoder: scaleDecoder))
        case 3:
            self = try .unavailable(Unavailable(scaleDecoder: scaleDecoder))
        case 4:
            self = try .cancelFilesRequest(requestId: UInt32(scaleDecoder: scaleDecoder))
        case 5:
            self = try .completed(requestId: UInt32(scaleDecoder: scaleDecoder))
        case 6:
            self = try .availabilityRequest(AvailabilityRequest(scaleDecoder: scaleDecoder))
        case 7:
            self = try .availabilityResponse(AvailabilityResponse(scaleDecoder: scaleDecoder))
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .filesRequest(request):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            try request.encode(scaleEncoder: scaleEncoder)
        case let .header(header):
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
            try header.encode(scaleEncoder: scaleEncoder)
        case let .chunk(chunk):
            try UInt8(2).encode(scaleEncoder: scaleEncoder)
            try chunk.encode(scaleEncoder: scaleEncoder)
        case let .unavailable(unavailable):
            try UInt8(3).encode(scaleEncoder: scaleEncoder)
            try unavailable.encode(scaleEncoder: scaleEncoder)
        case let .cancelFilesRequest(requestId):
            try UInt8(4).encode(scaleEncoder: scaleEncoder)
            try requestId.encode(scaleEncoder: scaleEncoder)
        case let .completed(requestId):
            try UInt8(5).encode(scaleEncoder: scaleEncoder)
            try requestId.encode(scaleEncoder: scaleEncoder)
        case let .availabilityRequest(request):
            try UInt8(6).encode(scaleEncoder: scaleEncoder)
            try request.encode(scaleEncoder: scaleEncoder)
        case let .availabilityResponse(response):
            try UInt8(7).encode(scaleEncoder: scaleEncoder)
            try response.encode(scaleEncoder: scaleEncoder)
        }
    }
}

// MARK: - ScaleCodable: file reference

extension Chat.DeviceSyncFileMessage.MessageAttachmentId: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        messageId = try String(scaleDecoder: scaleDecoder)
        identifier = try Data(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try messageId.encode(scaleEncoder: scaleEncoder)
        try identifier.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncFileMessage.FileReference: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = try .messageAttachment(
                Chat.DeviceSyncFileMessage.MessageAttachmentId(scaleDecoder: scaleDecoder)
            )
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .messageAttachment(attachmentId):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            try attachmentId.encode(scaleEncoder: scaleEncoder)
        }
    }
}

// MARK: - ScaleCodable: request

extension Chat.DeviceSyncFileMessage.RequestItem: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        file = try Chat.DeviceSyncFileMessage.FileReference(scaleDecoder: scaleDecoder)
        offset = try UInt64(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try file.encode(scaleEncoder: scaleEncoder)
        try offset.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncFileMessage.Request: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try UInt32(scaleDecoder: scaleDecoder)
        files = try [Chat.DeviceSyncFileMessage.RequestItem](scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try files.encode(scaleEncoder: scaleEncoder)
    }
}

// MARK: - ScaleCodable: transfer

extension Chat.DeviceSyncFileMessage.Header: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try UInt32(scaleDecoder: scaleDecoder)
        fileIndex = try UInt32(scaleDecoder: scaleDecoder)
        totalSize = try UInt64(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try fileIndex.encode(scaleEncoder: scaleEncoder)
        try totalSize.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncFileMessage.Chunk: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try UInt32(scaleDecoder: scaleDecoder)
        fileIndex = try UInt32(scaleDecoder: scaleDecoder)
        offset = try UInt64(scaleDecoder: scaleDecoder)
        data = try Data(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try fileIndex.encode(scaleEncoder: scaleEncoder)
        try offset.encode(scaleEncoder: scaleEncoder)
        try data.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncFileMessage.UnavailableReason: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let rawValue = try UInt8(scaleDecoder: scaleDecoder)
        guard let reason = Self(rawValue: rawValue) else {
            throw ScaleCodingError.unexpectedDecodedValue
        }
        self = reason
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try rawValue.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncFileMessage.Unavailable: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try UInt32(scaleDecoder: scaleDecoder)
        fileIndex = try UInt32(scaleDecoder: scaleDecoder)
        reason = try Chat.DeviceSyncFileMessage.UnavailableReason(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try fileIndex.encode(scaleEncoder: scaleEncoder)
        try reason.encode(scaleEncoder: scaleEncoder)
    }
}

// MARK: - ScaleCodable: availability

extension Chat.DeviceSyncFileMessage.AvailabilityRequest: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try UInt32(scaleDecoder: scaleDecoder)
        files = try [Chat.DeviceSyncFileMessage.FileReference](scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try files.encode(scaleEncoder: scaleEncoder)
    }
}

extension Chat.DeviceSyncFileMessage.Availability: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = try .available(totalSize: UInt64(scaleDecoder: scaleDecoder))
        case 1:
            self = try .unavailable(Chat.DeviceSyncFileMessage.UnavailableReason(scaleDecoder: scaleDecoder))
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .available(totalSize):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            try totalSize.encode(scaleEncoder: scaleEncoder)
        case let .unavailable(reason):
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
            try reason.encode(scaleEncoder: scaleEncoder)
        }
    }
}

extension Chat.DeviceSyncFileMessage.AvailabilityResponse: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try UInt32(scaleDecoder: scaleDecoder)
        availability = try [Chat.DeviceSyncFileMessage.Availability](scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try availability.encode(scaleEncoder: scaleEncoder)
    }
}
