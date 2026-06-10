import Foundation
import SubstrateSdk
import BigInt

public extension ResourcesPallet {
    struct ReservationQueueEntry: Decodable, Equatable {
        @BytesCodable public var account: AccountId
        @StringCodable public var joinedAt: BigUInt

        enum CodingKeys: String, CodingKey {
            case account
            case joinedAt = "joined_at"
        }
    }
}
