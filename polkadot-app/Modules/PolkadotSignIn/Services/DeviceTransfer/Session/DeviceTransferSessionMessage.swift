import Foundation
import SubstrateSdk

enum DeviceTransferSessionMessage: Equatable {
    case rejected
    case signaling(Chat.DeviceSyncSignalingEnvelope)
}

extension DeviceTransferSessionMessage: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = .rejected
        case 1:
            self = try .signaling(Chat.DeviceSyncSignalingEnvelope(scaleDecoder: scaleDecoder))
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case .rejected:
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
        case let .signaling(envelope):
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
            try envelope.encode(scaleEncoder: scaleEncoder)
        }
    }
}
