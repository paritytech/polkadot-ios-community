import BigInt
import Coinage
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("ClaimPlanMapper")
    struct ClaimPlanMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var repo: AnyDataProviderRepository<ClaimPlan> { facade.makeRepo(mapper: ClaimPlanMapper()) }

        private func makePlan(
            memoKey: Data = Data([1, 2, 3, 4]),
            messageId: String = "msg-test",
            entries: [ClaimPlanEntry] = [],
            status: ClaimPlan.Status = .processing,
            totalValue: BigUInt = 1_000,
            claimedAmount: BigUInt? = nil
        ) -> ClaimPlan {
            ClaimPlan(
                memoKey: memoKey,
                messageId: messageId,
                entries: entries,
                status: status,
                totalValue: totalValue,
                claimedAmount: claimedAmount
            )
        }

        @Test("roundTrip with two entries preserves entry fields")
        func roundTripWithEntries() async throws {
            let entries = [
                ClaimPlanEntry(entryIndex: 0, destinationCoin: Coin(exponent: 10, derivationIndex: 1, age: nil)),
                ClaimPlanEntry(entryIndex: 1, destinationCoin: Coin(exponent: 12, derivationIndex: 2, age: nil)),
            ]
            let original = makePlan(memoKey: Data([1, 2, 3, 4, 5]), messageId: "msg-123", entries: entries)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.memoKey == original.memoKey)
            #expect(result.messageId == original.messageId)
            #expect(result.entries.count == 2)
            #expect(result.entries[0].entryIndex == 0)
            #expect(result.entries[0].destinationCoin.exponent == 10)
            #expect(result.entries[0].destinationCoin.derivationIndex == 1)
            #expect(result.entries[1].entryIndex == 1)
            #expect(result.entries[1].destinationCoin.exponent == 12)
            #expect(result.entries[1].destinationCoin.derivationIndex == 2)
        }

        @Test("roundTrip with empty entries")
        func roundTripEmptyEntries() async throws {
            let original = makePlan(memoKey: Data([10, 20, 30]), status: .finished, totalValue: 5_000)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.entries.isEmpty)
        }

        @Test("nil claimedAmount round-trips as nil")
        func nilClaimedAmountRoundTrip() async throws {
            let original = makePlan(memoKey: Data([5, 6, 7]), claimedAmount: nil)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.claimedAmount == nil)
        }

        @Test("non-nil claimedAmount round-trips")
        func nonNilClaimedAmountRoundTrip() async throws {
            let original = makePlan(memoKey: Data([15, 16, 17]), totalValue: 3_000, claimedAmount: BigUInt(2_800))
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.claimedAmount == 2_800)
            #expect(result.totalValue == 3_000)
        }

        @Test("status .processing round-trips")
        func statusProcessing() async throws {
            let original = makePlan(memoKey: Data([1]), status: .processing)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()
            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.status == .processing)
        }

        @Test("status .finished round-trips")
        func statusFinished() async throws {
            let original = makePlan(memoKey: Data([2]), status: .finished, claimedAmount: BigUInt(200))
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()
            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.status == .finished)
        }

        @Test("status .error round-trips")
        func statusError() async throws {
            let original = makePlan(memoKey: Data([3]), status: .error)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()
            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.status == .error)
        }
    }

    // MARK: - ClaimPlanStatusMapper

    @Suite("ClaimPlanStatusMapper")
    struct ClaimPlanStatusMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var fullRepo: AnyDataProviderRepository<ClaimPlan> { facade.makeRepo(mapper: ClaimPlanMapper()) }
        private var statusRepo: AnyDataProviderRepository<ClaimPlan> { facade.makeRepo(mapper: ClaimPlanStatusMapper())
        }

        @Test("updates status and claimedAmount only")
        func updatesStatusAndClaimedAmountOnly() async throws {
            let entries = [
                ClaimPlanEntry(entryIndex: 0, destinationCoin: Coin(exponent: 10, derivationIndex: 20, age: nil)),
                ClaimPlanEntry(entryIndex: 1, destinationCoin: Coin(exponent: 12, derivationIndex: 21, age: nil)),
            ]
            let memoKey = Data([100, 101, 102])
            let original = ClaimPlan(
                memoKey: memoKey,
                messageId: "msg-status-test",
                entries: entries,
                status: .processing,
                totalValue: BigUInt(10_000),
                claimedAmount: nil
            )
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            let partial = ClaimPlan(
                memoKey: memoKey,
                messageId: "msg-status-test",
                entries: entries,
                status: .finished,
                totalValue: BigUInt(10_000),
                claimedAmount: BigUInt(999)
            )
            try await statusRepo.saveOperation({ [partial] }, { [] }).asyncExecute()

            let result = try #require(
                try await fullRepo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.status == .finished)
            #expect(result.claimedAmount == 999)
            #expect(result.memoKey == memoKey)
            #expect(result.messageId == "msg-status-test")
            #expect(result.entries.count == 2)
            #expect(result.totalValue == 10_000)
        }

        @Test("throws noExistingEntity")
        func throwsForNewEntity() async throws {
            let plan = ClaimPlan(
                memoKey: Data([200, 201]),
                messageId: "msg-new",
                entries: [],
                status: .finished,
                totalValue: BigUInt(5_555),
                claimedAmount: BigUInt(5_555)
            )

            await #expect(throws: ClaimPlanStatusMapper.MappingError.noExistingEntity) {
                try await statusRepo.saveOperation({ [plan] }, { [] }).asyncExecute()
            }
        }
    }
}
