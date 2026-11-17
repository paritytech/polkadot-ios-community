import Foundation
import SubstrateSdk

public protocol StatementAccountFunding {
    /// Local-only: whether the account's record was allocated or renewed for `period` or later.
    /// It does not read the chain, so an on-chain eviction is not reflected.
    func hasAllocation(accountId: AccountId, coveringPeriod period: UInt32) async throws -> Bool

    /// Funds `accountId` for the current period unless it already has a slot. `signerKeyId` references
    /// the key that signs as `accountId`; without it the slot can never be handed over to another account.
    func ensureFunded(
        accountId: AccountId,
        signerKeyId: String?,
        priority: AllowanceRecord.Priority,
        domain: AllowanceRecord.Domain
    ) async throws
}

public extension StatementAccountFunding {
    func ensureFunded(
        accountId: AccountId,
        priority: AllowanceRecord.Priority,
        domain: AllowanceRecord.Domain
    ) async throws {
        try await ensureFunded(accountId: accountId, signerKeyId: nil, priority: priority, domain: domain)
    }
}
