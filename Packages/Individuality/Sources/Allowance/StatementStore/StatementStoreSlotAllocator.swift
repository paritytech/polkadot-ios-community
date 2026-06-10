import Foundation
import SubstrateSdk
import KeyDerivation
import ChainStore

public final class StatementStoreSlotAllocator: AllowanceSlotAllocating {
    private let chainId: ChainId
    private let originFactory: AsResourcesOriginCreating
    private let submitter: SlotAssignmentSubmitting
    private let slotInfoProvider: StatementStoreSlotInfoProviding

    public init(
        chainId: ChainId,
        originFactory: AsResourcesOriginCreating,
        submitter: SlotAssignmentSubmitting,
        slotInfoProvider: StatementStoreSlotInfoProviding
    ) {
        self.chainId = chainId
        self.originFactory = originFactory
        self.submitter = submitter
        self.slotInfoProvider = slotInfoProvider
    }

    public func assignSlot(accountId: AccountId) async throws {
        let slot = try await slotInfoProvider.freeSlot(excluding: accountId)

        try await submitter.submit(
            call: ResourcesPallet.SetStatementStoreAccountCall(
                period: slot.period,
                seq: slot.seq,
                targetAccount: accountId
            )(),
            makeOrigin: { [originFactory] chainId in
                try await originFactory.createSSSOrigin(
                    personOrigin: slot.personOrigin,
                    period: slot.period,
                    seq: slot.seq,
                    chain: chainId
                )
            },
            chainId: chainId
        )
    }
}
