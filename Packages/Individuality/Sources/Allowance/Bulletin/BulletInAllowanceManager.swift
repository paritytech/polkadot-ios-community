import Foundation
import SubstrateSdk
import Operation_iOS
import StructuredConcurrency
import BackgroundExecution

public final class BulletInAllowanceManager {
    private let infoProvider: BulletInSlotInfoProviding
    private let allocator: AllowanceSlotAllocating
    private let backgroundExecutor: any BackgroundExecuting

    public init(
        infoProvider: BulletInSlotInfoProviding,
        allocator: AllowanceSlotAllocating,
        backgroundExecutor: any BackgroundExecuting
    ) {
        self.infoProvider = infoProvider
        self.allocator = allocator
        self.backgroundExecutor = backgroundExecutor
    }
}

extension BulletInAllowanceManager: AllowanceManaging {
    static let timeout: Duration = .seconds(60)

    public func allocate(
        accountId: AccountId,
        policy: OnExistingAllowancePolicy,
        priority: AllowanceRecord.Priority
    ) async throws {
        try await backgroundExecutor.execute { [allocator, infoProvider] in
            try await markStallActivity("Allocating Bulletin allowance") {
                let currentAllowance = try await markStallRegion("Check existing allowance") {
                    try await infoProvider.fetchAllowance(for: accountId)
                }

                if let currentAllowance, currentAllowance.available, policy == .ignore {
                    return
                }

                try await allocator.assignSlot(accountId: accountId, priority: priority)

                try await infoProvider.waitAuthorization(
                    for: accountId,
                    currentAllowance: currentAllowance,
                    timeout: Self.timeout
                )
            }
        }
    }
}
