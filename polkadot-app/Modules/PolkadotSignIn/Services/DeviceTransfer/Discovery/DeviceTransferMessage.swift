import Foundation
import SubstrateSdk

struct DeviceTransferRequest: Equatable {
    let requestId: String
    let deviceModel: String
    let operatingSystem: String
    let createdAt: UInt64
}

enum DeviceTransferMessage: Equatable {
    case request(DeviceTransferRequest)
    case cancel(requestId: String)
}

extension DeviceTransferRequest: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try String(scaleDecoder: scaleDecoder)
        deviceModel = try String(scaleDecoder: scaleDecoder)
        operatingSystem = try String(scaleDecoder: scaleDecoder)
        createdAt = try UInt64(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
        try deviceModel.encode(scaleEncoder: scaleEncoder)
        try operatingSystem.encode(scaleEncoder: scaleEncoder)
        try createdAt.encode(scaleEncoder: scaleEncoder)
    }
}

extension DeviceTransferMessage: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = try .request(DeviceTransferRequest(scaleDecoder: scaleDecoder))
        case 1:
            self = try .cancel(requestId: String(scaleDecoder: scaleDecoder))
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .request(request):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            try request.encode(scaleEncoder: scaleEncoder)
        case let .cancel(requestId):
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
            try requestId.encode(scaleEncoder: scaleEncoder)
        }
    }
}
