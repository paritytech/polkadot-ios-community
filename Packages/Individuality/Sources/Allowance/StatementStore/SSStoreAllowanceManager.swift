import Foundation
import SubstrateSdk
import Operation_iOS
import StructuredConcurrency

public final class SSStoreAllowanceManager {
    private let repository: AnyDataProviderRepository<AllowanceRecord>
    private let allocator: AllowanceSlotAllocating
    private let slotInfoProvider: StatementStoreSlotInfoProviding

    public init(
        repository: AnyDataProviderRepository<AllowanceRecord>,
        allocator: AllowanceSlotAllocating,
        slotInfoProvider: StatementStoreSlotInfoProviding
    ) {
        self.repository = repository
        self.allocator = allocator
        self.slotInfoProvider = slotInfoProvider
    }
}

extension SSStoreAllowanceManager: AllowanceManaging {
    public func allocate(
        accountId: AccountId,
        policy: OnExistingAllowancePolicy
    ) async throws {
        if policy == .ignore, try await slotInfoProvider.hasExistingSlot(for: accountId) {
            return
        }

        try await allocator.assignSlot(accountId: accountId)

        let record = AllowanceRecord(accountId: accountId, allocatedAt: Date())
        try await repository.saveOperation({ [record] }, { [] }).asyncExecute()
    }
}
