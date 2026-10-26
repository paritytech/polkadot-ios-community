import Foundation
import SubstrateSdk

enum DeviceTransferAbortReason: UInt8, Equatable {
    case userCancelled = 0
    case internalError = 1
}

/// The `deviceTransfer` use case on the data channel (RFC §7.2). `senderStarted` opens every connection and
/// carries the device key before any sync update; `resume` tells the sender where the receiver's database stands.
enum DeviceTransferControl: Equatable {
    static let deviceEncryptionKeyLength = 32

    case senderStarted(deviceEncryptionKey: Data, totalChanges: UInt32)
    case senderCompleted
    case receiverCompleted
    case abort(DeviceTransferAbortReason)
    /// `nil` when the receiver holds nothing yet, so the sender starts from the beginning.
    case resume(fromTimePoint: UInt64?)
}

extension DeviceTransferAbortReason: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        guard let reason = try Self(rawValue: UInt8(scaleDecoder: scaleDecoder)) else {
            throw ScaleCodingError.unexpectedDecodedValue
        }
        self = reason
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try rawValue.encode(scaleEncoder: scaleEncoder)
    }
}

extension DeviceTransferControl: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = try .senderStarted(
                deviceEncryptionKey: scaleDecoder.readAndConfirm(count: Self.deviceEncryptionKeyLength),
                totalChanges: UInt32(scaleDecoder: scaleDecoder)
            )
        case 1:
            self = .senderCompleted
        case 2:
            self = .receiverCompleted
        case 3:
            self = try .abort(DeviceTransferAbortReason(scaleDecoder: scaleDecoder))
        case 4:
            self = try .resume(fromTimePoint: ScaleOption<UInt64>(scaleDecoder: scaleDecoder).value)
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .senderStarted(deviceEncryptionKey, totalChanges):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            scaleEncoder.appendRaw(data: deviceEncryptionKey)
            try totalChanges.encode(scaleEncoder: scaleEncoder)
        case .senderCompleted:
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
        case .receiverCompleted:
            try UInt8(2).encode(scaleEncoder: scaleEncoder)
        case let .abort(reason):
            try UInt8(3).encode(scaleEncoder: scaleEncoder)
            try reason.encode(scaleEncoder: scaleEncoder)
        case let .resume(fromTimePoint):
            try UInt8(4).encode(scaleEncoder: scaleEncoder)
            try ScaleOption(value: fromTimePoint).encode(scaleEncoder: scaleEncoder)
        }
    }
}
