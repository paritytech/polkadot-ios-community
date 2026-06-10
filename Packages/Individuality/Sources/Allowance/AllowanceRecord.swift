import Foundation
import SubstrateSdk
import Operation_iOS

public struct AllowanceRecord: Equatable {
    public let accountId: AccountId
    public let allocatedAt: Date

    public init(accountId: AccountId, allocatedAt: Date) {
        self.accountId = accountId
        self.allocatedAt = allocatedAt
    }
}

extension AllowanceRecord: Identifiable {
    public var identifier: String { accountId.toHex() }
}
