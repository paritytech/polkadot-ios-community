import Foundation
import SubstrateSdk
import SubstrateSdkExt

public enum MembersSubscriberPallet {
    public static let name = "MembersSubscriber"
}

// MARK: - Storage

public extension MembersSubscriberPallet {
    enum Storage {
        case ringRoots
    }
}

extension MembersSubscriberPallet.Storage: StoragePathConvertible {
    public var name: String {
        switch self {
        case .ringRoots:
            "RingRoots"
        }
    }

    public var moduleName: String { MembersSubscriberPallet.name }
}

// MARK: - Types

public extension MembersSubscriberPallet {
    struct RingCommitmentRecord: Decodable {
        @BytesCodable public var root: Data
        @StringCodable public var revision: UInt32
    }
}
