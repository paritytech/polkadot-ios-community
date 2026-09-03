import Foundation
import SubstrateSdk
import Operation_iOS
import StructuredConcurrency
import BackgroundExecution
import SDKLogger

public final class BulletInAllowanceManager {
    private let infoProvider: BulletInSlotInfoProviding
    private let allocator: AllowanceSlotAllocating
    private let backgroundExecutor: any BackgroundExecuting
    private let logger: SDKLoggerProtocol
    private let claimCoordinator = PromotionClaimCoordinator()

    public init(
        infoProvider: BulletInSlotInfoProviding,
        allocator: AllowanceSlotAllocating,
        backgroundExecutor: any BackgroundExecuting,
        logger: SDKLoggerProtocol
    ) {
        self.infoProvider = infoProvider
        self.allocator = allocator
        self.backgroundExecutor = backgroundExecutor
        self.logger = logger
    }
}

extension BulletInAllowanceManager: AllowanceManaging {
    static let timeout: Duration = .seconds(60)
    // Overall bound for one coalesced check-and-claim, so a stalled claim can never keep the
    // in-flight task (and every upload coalesced onto it) waiting forever.
    static let claimTimeout: Duration = .seconds(120)

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

    /// Gates on `HopRuntimeApi.can_account_promote` instead of the stored allowance extent: HOP promotion
    /// requires an unexpired authorization; the remaining extent is not checked. Products keep using
    /// [allocate], which reads the extent to honour capacity.
    public func ensurePromotable(
        accountId: AccountId,
        priority: AllowanceRecord.Priority
    ) async throws {
        // Coalesce overlapping calls for the same account: a second upload started while the first is
        // still claiming shares that in-flight check-and-claim instead of claiming a redundant slot.
        try await claimCoordinator.coalesce(for: accountId, within: Self.claimTimeout) { [
            backgroundExecutor,
            allocator,
            infoProvider,
            logger
        ] in
            try await backgroundExecutor.execute {
                try await markStallActivity("Ensuring Bulletin promotion allowance") {
                    let promotable = try await markStallRegion("Check promotion eligibility") {
                        try await infoProvider.canAccountPromote(for: accountId)
                    }

                    guard !promotable else {
                        logger.debug("HOP promotion: can_account_promote=true, skipping claim")
                        return
                    }

                    logger.debug("HOP promotion: can_account_promote=false, claiming long-term storage slot")
                    try await allocator.assignSlot(accountId: accountId, priority: priority)

                    try await infoProvider.waitPromotable(for: accountId, timeout: Self.timeout)
                    logger.debug("HOP promotion: authorization active on bulletin after claim")
                }
            }
        }
    }
}

/// Serializes the promotion check-and-claim per account so concurrent uploads coalesce onto one
/// in-flight operation instead of each submitting a redundant `claim_long_term_storage`.
private actor PromotionClaimCoordinator {
    private var inFlight: [AccountId: Task<Void, Error>] = [:]

    func coalesce(
        for accountId: AccountId,
        within timeout: Duration,
        operation: @Sendable @escaping () async throws -> Void
    ) async throws {
        if let existing = inFlight[accountId] {
            return try await existing.value
        }

        let task = Task { try await withTimeout(timeout) { try await operation() } }
        inFlight[accountId] = task
        defer { inFlight[accountId] = nil }

        try await task.value
    }
}
