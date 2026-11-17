import Foundation
import SubstrateSdk
import KeyDerivation
import ChainStore
import ExtrinsicService
import StructuredConcurrency

public final class StatementStoreSlotAllocator: AllowanceSlotAllocating {
    /// Candidates are ordered oldest-first, so a rate-limited one is almost always the slot this
    /// installation just replaced; a few tries cover that without walking every slot.
    static let maxReplacementAttempts = 3
    /// `StmtStoreReplacementTooEarly`: the slot entry was written in the current block.
    static let tooEarlyValidityCode: UInt8 = 228

    private let chainId: ChainId
    private let originFactory: AsResourcesOriginCreating
    private let submitter: SlotAssignmentSubmitting
    private let slotInfoProvider: StatementStoreSlotInfoProviding
    private let replacementValidator: SlotReplacementValidating
    private let serialQueue: SerialOperationQueue

    public init(
        chainId: ChainId,
        originFactory: AsResourcesOriginCreating,
        submitter: SlotAssignmentSubmitting,
        slotInfoProvider: StatementStoreSlotInfoProviding,
        replacementValidator: SlotReplacementValidating,
        serialQueue: SerialOperationQueue
    ) {
        self.chainId = chainId
        self.originFactory = originFactory
        self.submitter = submitter
        self.slotInfoProvider = slotInfoProvider
        self.replacementValidator = replacementValidator
        self.serialQueue = serialQueue
    }

    public func assignSlot(accountId: AccountId, priority: AllowanceRecord.Priority) async throws -> UInt32 {
        try await markStallRegion("Reserving SS slot") {
            try await serialQueue.run { [weak self] in
                guard let self else { throw AllowanceSlotAssignmentError.noSlotsAvailable }

                let plan = try await markStallRegion("Reading chain state") {
                    try await self.slotInfoProvider.slotPlan(excluding: accountId, callerPriority: priority)
                }

                switch plan {
                case let .free(slot):
                    try await claimFreeSlot(slot, accountId: accountId)
                    return slot.period
                case let .evict(period, candidates):
                    try await replaceSlot(period: period, candidates: candidates, accountId: accountId)
                    return period
                }
            }
        }
    }
}

private extension StatementStoreSlotAllocator {
    func claimFreeSlot(_ slot: SSSSlotInfo, accountId: AccountId) async throws {
        let callData = ResourcesPallet.SetStatementStoreAccountCall(
            period: slot.period,
            seq: slot.seq,
            targetAccount: accountId
        )()

        try await markStallRegion("Submitting") {
            try await submitter.submit(
                call: callData,
                makeOrigin: { [originFactory] chain in
                    try await originFactory.createSSSOrigin(
                        personOrigin: slot.personOrigin,
                        period: slot.period,
                        seq: slot.seq,
                        chain: chain
                    )
                },
                chainId: chainId
            )
        }
    }

    func replaceSlot(period: UInt32, candidates: [SSSEvictionCandidate], accountId: AccountId) async throws {
        for candidate in candidates.prefix(Self.maxReplacementAttempts) {
            let callData = ResourcesPallet.ReplaceStatementStoreAccountCall(
                period: period,
                alias: candidate.alias,
                newAccount: accountId,
                since: candidate.since
            )()

            let makeOrigin: @Sendable (ChainId) async throws -> ExtrinsicOriginDefining = { [originFactory] chain in
                try await originFactory.createStmtStoreHolderOrigin(
                    signerKeyId: candidate.signerKeyId,
                    holder: candidate.holder,
                    chain: chain
                )
            }

            let validity = try await markStallRegion("Validating replacement") {
                try await replacementValidator.validate(call: callData, origin: makeOrigin(chainId), chainId: chainId)
            }

            switch validity {
            case .invalid(.payment),
                 .invalid(.custom(Self.tooEarlyValidityCode)):
                continue
            case let .invalid(reason):
                throw StatementStoreAllowanceError.replacementRejected(reason)
            case .valid,
                 .inconclusive:
                try await markStallRegion("Submitting") {
                    try await submitter.submit(call: callData, makeOrigin: makeOrigin, chainId: chainId)
                }
                return
            }
        }

        throw StatementStoreAllowanceError.noSlotsAvailable
    }
}
