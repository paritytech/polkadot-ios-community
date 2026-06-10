import Foundation
import SubstrateSdk
import Operation_iOS
import StructuredConcurrency

public final class BulletInAllowanceManager {
    private let infoProvider: BulletInSlotInfoProviding
    private let allocator: AllowanceSlotAllocating

    public init(
        infoProvider: BulletInSlotInfoProviding,
        allocator: AllowanceSlotAllocating
    ) {
        self.infoProvider = infoProvider
        self.allocator = allocator
    }
}

extension BulletInAllowanceManager: AllowanceManaging {
    static let timeout: Duration = .seconds(60)

    public func allocate(
        accountId: AccountId,
        policy: OnExistingAllowancePolicy
    ) async throws {
        let currentAllowance = try await infoProvider.fetchAllowance(for: accountId)

        if let currentAllowance, currentAllowance.available, policy == .ignore {
            return
        }

        try await allocator.assignSlot(accountId: accountId)

        try await infoProvider.waitAuthorization(
            for: accountId,
            currentAllowance: currentAllowance,
            timeout: Self.timeout
        )
    }
}
