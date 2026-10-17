import Foundation
import SubstrateSdk

// MARK: - RequestDeviceInfo

/// Per-device encrypted symmetric key entry.
/// Each entry holds the statement store account ID of a target device
/// and the one-shot symmetric key encrypted with that device's P-256 public key.
public struct RequestDeviceInfo: Equatable {
    public let statementAccountId: Data
    public let encryptedKey: Data

    public init(
        statementAccountId: Data,
        encryptedKey: Data
    ) {
        self.statementAccountId = statementAccountId
        self.encryptedKey = encryptedKey
    }
}

extension RequestDeviceInfo: ScaleCodable {
    static let statementAccountIdLength = 32

    public init(scaleDecoder: any ScaleDecoding) throws {
        statementAccountId = try scaleDecoder.readAndConfirm(count: Self.statementAccountIdLength)
        encryptedKey = try Data(scaleDecoder: scaleDecoder)
    }

    public func encode(scaleEncoder: any ScaleEncoding) throws {
        scaleEncoder.appendRaw(data: statementAccountId)
        try encryptedKey.encode(scaleEncoder: scaleEncoder)
    }
}

// MARK: - MultiDeviceState

/// Multi-device state envelope.
/// `encryptedState` is a `SessionState<M>` sealed with a one-shot ChaCha20-Poly1305 key,
/// and `devicesInfo` carries that key encrypted for each recipient device.
public struct MultiDeviceState: Equatable {
    public let encryptedState: Data
    public let devicesInfo: [RequestDeviceInfo]

    public init(
        encryptedState: Data,
        devicesInfo: [RequestDeviceInfo]
    ) {
        self.encryptedState = encryptedState
        self.devicesInfo = devicesInfo
    }
}

extension MultiDeviceState: ScaleCodable {
    public init(scaleDecoder: any ScaleDecoding) throws {
        encryptedState = try Data(scaleDecoder: scaleDecoder)
        devicesInfo = try [RequestDeviceInfo](scaleDecoder: scaleDecoder)
    }

    public func encode(scaleEncoder: any ScaleEncoding) throws {
        try encryptedState.encode(scaleEncoder: scaleEncoder)
        try devicesInfo.encode(scaleEncoder: scaleEncoder)
    }
}
