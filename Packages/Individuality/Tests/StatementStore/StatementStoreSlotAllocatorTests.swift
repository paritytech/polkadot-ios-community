import Foundation
import SubstrateSdk
import SubstrateOperation
import StructuredConcurrency
import Testing
@testable import Individuality

struct StatementStoreSlotAllocatorTests {
    private let keyManager = FakeBandersnatchKeyManaging()
    private let chainId = "polkadot"
    private let accountId = Data(repeating: 0x01, count: 32)
    private let period: UInt32 = 100

    @Test func freeSlotIsClaimedWithSetCall() async throws {
        let submitter = FakeSubmitter()
        let validator = FakeReplacementValidator(script: [.valid])
        let originFactory = FakeOriginFactory()
        let allocator = makeAllocator(
            plan: .free(SSSSlotInfo(period: period, seq: 5, personOrigin: .lite(0, keyManager))),
            submitter: submitter,
            validator: validator,
            originFactory: originFactory
        )

        let outcome = try await allocator.assignSlot(accountId: accountId, priority: .normal)

        #expect(outcome == period)
        #expect(submitter.submittedCalls.map(\.callName) == ["set_statement_store_account"])
        #expect(originFactory.sssOriginCalls.map(\.seq) == [5])
        #expect(validator.validatedCalls.isEmpty)
    }

    @Test func occupiedSlotIsReplacedWithFirstValidCandidate() async throws {
        let submitter = FakeSubmitter()
        let validator = FakeReplacementValidator(script: [.valid])
        let originFactory = FakeOriginFactory()
        let candidates = [makeCandidate(seq: 0, since: 10), makeCandidate(seq: 1, since: 20)]
        let allocator = makeAllocator(
            plan: .evict(period: period, candidates: candidates),
            submitter: submitter,
            validator: validator,
            originFactory: originFactory
        )

        let outcome = try await allocator.assignSlot(accountId: accountId, priority: .normal)

        #expect(outcome == period)
        #expect(validator.validatedCalls.count == 1)
        let submitted = try #require(
            submitter.submittedCalls.last as? RuntimeCall<ResourcesPallet.ReplaceStatementStoreAccountCall>
        )
        #expect(submitted.callName == "replace_statement_store_account")
        #expect(submitted.args.period == period)
        #expect(submitted.args.alias == candidates[0].alias)
        #expect(submitted.args.since == 10)
        #expect(submitted.args.newAccount == accountId)
        #expect(originFactory.holderOriginCalls.last?.signerKeyId == candidates[0].signerKeyId)
        #expect(originFactory.holderOriginCalls.last?.holder == candidates[0].holder)
    }

    @Test(arguments: [SlotReplacementValidity.invalid(.payment), .invalid(.custom(228))])
    func rateLimitedCandidateIsSkipped(firstAnswer: SlotReplacementValidity) async throws {
        let submitter = FakeSubmitter()
        let validator = FakeReplacementValidator(script: [firstAnswer, .valid])
        let originFactory = FakeOriginFactory()
        let candidates = [makeCandidate(seq: 0, since: 10), makeCandidate(seq: 1, since: 20)]
        let allocator = makeAllocator(
            plan: .evict(period: period, candidates: candidates),
            submitter: submitter,
            validator: validator,
            originFactory: originFactory
        )

        try await allocator.assignSlot(accountId: accountId, priority: .normal)

        #expect(validator.validatedCalls.count == 2)
        let submitted = try #require(
            submitter.submittedCalls.last as? RuntimeCall<ResourcesPallet.ReplaceStatementStoreAccountCall>
        )
        #expect(submitted.args.since == 20)
        #expect(submitter.submittedCalls.count == 1)
    }

    @Test func otherRejectionAbortsWithoutSubmitting() async throws {
        let submitter = FakeSubmitter()
        let validator = FakeReplacementValidator(script: [.invalid(.custom(237))])
        let allocator = makeAllocator(
            plan: .evict(
                period: period,
                candidates: [makeCandidate(seq: 0, since: 10), makeCandidate(seq: 1, since: 20)]
            ),
            submitter: submitter,
            validator: validator,
            originFactory: FakeOriginFactory()
        )

        await #expect(throws: StatementStoreAllowanceError.replacementRejected(.custom(237))) {
            try await allocator.assignSlot(accountId: accountId, priority: .normal)
        }
        #expect(validator.validatedCalls.count == 1)
        #expect(submitter.submittedCalls.isEmpty)
    }

    @Test func everyCandidateRateLimitedThrowsNoSlotsAvailableAfterCappedAttempts() async throws {
        let submitter = FakeSubmitter()
        let validator = FakeReplacementValidator(script: [.invalid(.payment)])
        let candidates = (0 ..< 5).map { makeCandidate(seq: UInt32($0), since: UInt64($0)) }
        let allocator = makeAllocator(
            plan: .evict(period: period, candidates: candidates),
            submitter: submitter,
            validator: validator,
            originFactory: FakeOriginFactory()
        )

        await #expect(throws: StatementStoreAllowanceError.noSlotsAvailable) {
            try await allocator.assignSlot(accountId: accountId, priority: .normal)
        }
        #expect(validator.validatedCalls.count == StatementStoreSlotAllocator.maxReplacementAttempts)
        #expect(submitter.submittedCalls.isEmpty)
    }

    @Test func inconclusiveDryRunProceedsToSubmit() async throws {
        let submitter = FakeSubmitter()
        let validator = FakeReplacementValidator(script: [.inconclusive])
        let allocator = makeAllocator(
            plan: .evict(period: period, candidates: [makeCandidate(seq: 0, since: 10)]),
            submitter: submitter,
            validator: validator,
            originFactory: FakeOriginFactory()
        )

        let outcome = try await allocator.assignSlot(accountId: accountId, priority: .normal)

        #expect(outcome == period)
        #expect(submitter.submittedCalls.map(\.callName) == ["replace_statement_store_account"])
    }

    @Test func noSlotsAvailableThrowsError() async throws {
        let allocator = makeAllocator(
            planResult: .failure(AllowanceSlotAssignmentError.noSlotsAvailable),
            submitter: FakeSubmitter(),
            validator: FakeReplacementValidator(script: [.valid]),
            originFactory: FakeOriginFactory()
        )

        await #expect(throws: AllowanceSlotAssignmentError.self) {
            try await allocator.assignSlot(accountId: accountId, priority: .normal)
        }
    }
}

private extension StatementStoreSlotAllocatorTests {
    func makeAllocator(
        plan: SSSSlotPlan,
        submitter: FakeSubmitter,
        validator: FakeReplacementValidator,
        originFactory: FakeOriginFactory
    ) -> StatementStoreSlotAllocator {
        makeAllocator(
            planResult: .success(plan),
            submitter: submitter,
            validator: validator,
            originFactory: originFactory
        )
    }

    func makeAllocator(
        planResult: Result<SSSSlotPlan, Error>,
        submitter: FakeSubmitter,
        validator: FakeReplacementValidator,
        originFactory: FakeOriginFactory
    ) -> StatementStoreSlotAllocator {
        let slotProvider = FakeSlotInfoProvider()
        slotProvider.updateSlotPlan(planResult)

        return StatementStoreSlotAllocator(
            chainId: chainId,
            originFactory: originFactory,
            submitter: submitter,
            slotInfoProvider: slotProvider,
            replacementValidator: validator,
            serialQueue: SerialOperationQueue()
        )
    }

    func makeCandidate(seq: UInt32, since: UInt64) -> SSSEvictionCandidate {
        SSSEvictionCandidate(
            personOrigin: .lite(0, keyManager),
            seq: seq,
            alias: Data(repeating: UInt8(seq), count: 32),
            holder: Data(repeating: 0xA0 + UInt8(seq), count: 32),
            since: since,
            signerKeyId: "//slot//\(seq)"
        )
    }
}
