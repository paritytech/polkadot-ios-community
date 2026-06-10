import BigInt
import Foundation
import SubstrateSdk

/// Persistence layer for claim plans.
///
/// Implementations store plans in a durable backend (e.g. CoreData) so that
/// in-progress claims survive app restarts and their statuses can be restored.
public protocol ClaimPlanStoring: Sendable {
    func save(plan: ClaimPlan) async throws
    func loadAll() async throws -> [ClaimPlan]
    func remove(memo: TransferMemo) async throws
    func plan(memo: TransferMemo) async throws -> ClaimPlan?
    func updateStatus(
        _ status: ClaimPlan.Status,
        claimedAmount: Balance?,
        forMemo memo: TransferMemo
    ) async throws
}

extension ClaimPlanStoring {
    func updateStatus(
        _ status: ClaimPlan.Status,
        forMemo memo: TransferMemo
    ) async throws {
        try await updateStatus(status, claimedAmount: nil, forMemo: memo)
    }
}
