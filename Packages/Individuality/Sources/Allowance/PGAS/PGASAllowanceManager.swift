import Foundation
import SubstrateSdk
import Operation_iOS
import StructuredConcurrency

public final class PGASAllowanceManager {
    private let repository: AnyDataProviderRepository<AllowanceRecord>
    private let allocator: AllowanceSlotAllocating
    private let slotInfoProvider: PGASSlotInfoProviding

    public init(
        repository: AnyDataProviderRepository<AllowanceRecord>,
        allocator: AllowanceSlotAllocating,
        slotInfoProvider: PGASSlotInfoProviding
    ) {
        self.repository = repository
        self.allocator = allocator
        self.slotInfoProvider = slotInfoProvider
    }
}

extension PGASAllowanceManager: AllowanceManaging {
    public func allocate(
        accountId: AccountId,
        policy _: OnExistingAllowancePolicy
    ) async throws {
        // TODO: Should save allocation locally and check if we have it
        // always allocate new slot for now
//        if policy == .ignore, try await slotInfoProvider.hasExistingSlot(for: accountId) {
//            return
//        }

        try await allocator.assignSlot(accountId: accountId)

        let record = AllowanceRecord(accountId: accountId, allocatedAt: Date())
        try await repository.saveOperation({ [record] }, { [] }).asyncExecute()
    }
}
