import Foundation
import SubstrateSdk
import KeyDerivation
import ChainStore

public final class PGASSlotAllocator: AllowanceSlotAllocating {
    private let submissionChainId: ChainId
    private let originChainId: ChainId
    private let originFactory: PGasOriginCreating
    private let submitter: SlotAssignmentSubmitting
    private let slotInfoProvider: PGASSlotInfoProviding

    public init(
        submissionChainId: ChainId,
        originChainId: ChainId,
        originFactory: PGasOriginCreating,
        submitter: SlotAssignmentSubmitting,
        slotInfoProvider: PGASSlotInfoProviding
    ) {
        self.submissionChainId = submissionChainId
        self.originChainId = originChainId
        self.originFactory = originFactory
        self.submitter = submitter
        self.slotInfoProvider = slotInfoProvider
    }

    public func assignSlot(accountId: AccountId) async throws {
        let slot = try await slotInfoProvider.freeSlot()

        try await submitter.submit(
            call: PGASPallet.ClaimPgasCall(
                slotIndex: slot.slotIndex,
                target: accountId
            )(),
            makeOrigin: { [originFactory, slot, originChainId, submissionChainId] _ in
                try await originFactory.createPGASOrigin(
                    personOrigin: slot.personOrigin,
                    day: slot.day,
                    slotIndex: slot.slotIndex,
                    peopleChainId: originChainId,
                    submissionChainId: submissionChainId
                )
            },
            chainId: submissionChainId
        )
    }
}
