import Foundation
import SubstrateSdk

/// The record naming the user's active installation (Device Transfer RFC §8).
struct ActiveInstallation: Equatable {
    static let installationIdSize = 32

    let installationId: Data
    let deviceModel: String
    let operatingSystem: String
    /// Milliseconds since the Unix epoch.
    let activatedAt: UInt64
}

extension ActiveInstallation: Comparable {
    /// The current record has the greatest `activatedAt`; ties go to the greater installation id. The remaining
    /// fields only keep the order consistent with `==`.
    static func < (lhs: ActiveInstallation, rhs: ActiveInstallation) -> Bool {
        if lhs.activatedAt != rhs.activatedAt {
            return lhs.activatedAt < rhs.activatedAt
        }

        if lhs.installationId != rhs.installationId {
            return lhs.installationId.lexicographicallyPrecedes(rhs.installationId)
        }

        return (lhs.deviceModel, lhs.operatingSystem) < (rhs.deviceModel, rhs.operatingSystem)
    }
}

enum VersionedActiveDevice: Equatable {
    // swiftlint:disable:next identifier_name
    case v1(ActiveInstallation)
}

extension ActiveInstallation: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        installationId = try scaleDecoder.readAndConfirm(count: Self.installationIdSize)
        deviceModel = try String(scaleDecoder: scaleDecoder)
        operatingSystem = try String(scaleDecoder: scaleDecoder)
        activatedAt = try UInt64(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        guard installationId.count == Self.installationIdSize else {
            throw ScaleCodingError.unexpectedDecodedValue
        }

        scaleEncoder.appendRaw(data: installationId)
        try deviceModel.encode(scaleEncoder: scaleEncoder)
        try operatingSystem.encode(scaleEncoder: scaleEncoder)
        try activatedAt.encode(scaleEncoder: scaleEncoder)
    }
}

extension VersionedActiveDevice: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)
        switch index {
        case 0:
            self = try .v1(ActiveInstallation(scaleDecoder: scaleDecoder))
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .v1(installation):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            try installation.encode(scaleEncoder: scaleEncoder)
        }
    }
}
