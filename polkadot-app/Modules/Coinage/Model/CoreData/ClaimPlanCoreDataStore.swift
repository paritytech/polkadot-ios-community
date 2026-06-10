import BigInt
import Coinage
import CoreData
import Foundation
import Operation_iOS
import SubstrateSdk

/// CoreData-backed implementation of ``ClaimPlanStoring``.
///
/// Persists claim plans as `CDClaimPlan` entities with SCALE-encoded entries.
/// Used to restore claim statuses on app startup and to recover interrupted claims.
final class ClaimPlanCoreDataStore: ClaimPlanStoring, @unchecked Sendable {
    private let repository: AnyDataProviderRepository<ClaimPlan>
    private let statusUpdateRepository: AnyDataProviderRepository<ClaimPlan>

    init(storageFacade: StorageFacadeProtocol) {
        let coreDataRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(ClaimPlanMapper())
        )
        repository = AnyDataProviderRepository(coreDataRepository)

        let statusCoreDataRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(ClaimPlanStatusMapper())
        )
        statusUpdateRepository = AnyDataProviderRepository(statusCoreDataRepository)
    }

    func save(plan: ClaimPlan) async throws {
        try await repository.saveOperation({ [plan] }, { [] }).asyncExecute()
    }

    func loadAll() async throws -> [ClaimPlan] {
        try await repository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }

    func remove(memo: TransferMemo) async throws {
        try await repository.saveOperation(
            { [] },
            { [memo.identifier().toHex()] }
        )
        .asyncExecute()
    }

    func plan(memo: TransferMemo) async throws -> ClaimPlan? {
        try await repository.fetchOperation(
            by: { memo.identifier().toHex() },
            options: .init()
        )
        .asyncExecute()
    }

    func updateStatus(
        _ status: ClaimPlan.Status,
        claimedAmount: Balance? = nil,
        forMemo memo: TransferMemo
    ) async throws {
        let existing = try await repository.fetchOperation(
            by: { memo.identifier().toHex() },
            options: .init()
        )
        .asyncExecute()

        guard let existing else { return }

        let plan = ClaimPlan(
            memoKey: existing.memoKey,
            messageId: existing.messageId,
            entries: existing.entries,
            status: status,
            totalValue: existing.totalValue,
            claimedAmount: claimedAmount ?? existing.claimedAmount
        )
        try await statusUpdateRepository.saveOperation({ [plan] }, { [] }).asyncExecute()
    }
}
