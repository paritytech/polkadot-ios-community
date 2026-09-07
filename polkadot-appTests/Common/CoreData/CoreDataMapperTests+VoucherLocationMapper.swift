import BigInt
import Coinage
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("VoucherLocationMapper")
    struct VoucherLocationMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var fullRepo: AnyDataProviderRepository<Voucher> { facade.makeRepo(mapper: VoucherMapper()) }
        private var locationRepo: AnyDataProviderRepository<VoucherLocationUpdate> {
            facade.makeRepo(mapper: VoucherLocationMapper())
        }

        /// Helper: a voucher with no ring yet, which is how one is minted.
        private func unlocatedVoucher(index: DerivationIndex) -> Voucher {
            let now = Date(timeIntervalSinceReferenceDate: 3_000_000)

            return Voucher(
                exponent: 5,
                derivationIndex: index,
                allocatedAt: now,
                readyAt: now.addingTimeInterval(600),
                remoteState: .unlocated,
                publicKey: Data(repeating: 0x71, count: 32)
            )
        }

        private func stored(_ voucher: Voucher) async throws -> Voucher {
            try #require(
                try await fullRepo
                    .fetchOperation(by: { voucher.identifier }, options: .init())
                    .asyncExecute()
            )
        }

        @Test("captures the ceiling when the voucher first lands in a ring")
        func capturesCeilingOnRingEntry() async throws {
            let original = unlocatedVoucher(index: 300)
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            try await locationRepo.saveOperation({
                [VoucherLocationUpdate(
                    derivationIndex: 300,
                    remoteState: .inRecycler(.init(index: 7, membersCount: 40)),
                    recyclerFungibility: 55,
                    maxRecyclerFungibility: 80
                )]
            }, { [] }).asyncExecute()

            let result = try await stored(original)
            #expect(result.maxRecyclerFungibility == 80)
            #expect(result.recyclerFungibility == 55)
        }

        /// Zero is a legitimate ceiling for a fully drained ring, so it must not be mistaken for
        /// "nothing captured yet" and overwritten by a later, more favourable reading.
        @Test("a ceiling of zero stays frozen when a later reading is positive")
        func zeroCeilingStaysFrozen() async throws {
            let original = unlocatedVoucher(index: 301)
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            let ring = Voucher.OnChainState.inRecycler(.init(index: 9, membersCount: 12))

            // First presence in ring 9: the ring is drained, so the ceiling is genuinely zero.
            try await locationRepo.saveOperation({
                [VoucherLocationUpdate(
                    derivationIndex: 301,
                    remoteState: ring,
                    recyclerFungibility: 0,
                    maxRecyclerFungibility: 0
                )]
            }, { [] }).asyncExecute()

            #expect(try await stored(original).maxRecyclerFungibility == 0)

            // A later look at the same ring reports better numbers — the chain decrements its
            // unloaded count on a failed dispatch. The frozen ceiling must not move.
            try await locationRepo.saveOperation({
                [VoucherLocationUpdate(
                    derivationIndex: 301,
                    remoteState: ring,
                    recyclerFungibility: 42,
                    maxRecyclerFungibility: 90
                )]
            }, { [] }).asyncExecute()

            let result = try await stored(original)
            #expect(result.maxRecyclerFungibility == 0)
            // The current score is not frozen, so it does track the newer reading.
            #expect(result.recyclerFungibility == 42)
        }

        @Test("a ceiling is recaptured when the voucher is placed in a different ring")
        func recapturesCeilingOnRingChange() async throws {
            let original = unlocatedVoucher(index: 302)
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            try await locationRepo.saveOperation({
                [VoucherLocationUpdate(
                    derivationIndex: 302,
                    remoteState: .inRecycler(.init(index: 1, membersCount: 10)),
                    recyclerFungibility: 20,
                    maxRecyclerFungibility: 30
                )]
            }, { [] }).asyncExecute()

            // A different ring is a different anonymity set, so its ceiling is a new fact.
            try await locationRepo.saveOperation({
                [VoucherLocationUpdate(
                    derivationIndex: 302,
                    remoteState: .inRecycler(.init(index: 2, membersCount: 60)),
                    recyclerFungibility: 70,
                    maxRecyclerFungibility: 95
                )]
            }, { [] }).asyncExecute()

            #expect(try await stored(original).maxRecyclerFungibility == 95)
        }

        @Test("a location-only update leaves both scores untouched")
        func locationOnlyUpdateKeepsScores() async throws {
            let original = unlocatedVoucher(index: 303)
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            try await locationRepo.saveOperation({
                [VoucherLocationUpdate(
                    derivationIndex: 303,
                    remoteState: .inRecycler(.init(index: 4, membersCount: 20)),
                    recyclerFungibility: 61,
                    maxRecyclerFungibility: 77
                )]
            }, { [] }).asyncExecute()

            // Same ring, no scores resolved this tick: neither field may be disturbed.
            try await locationRepo.saveOperation({
                [VoucherLocationUpdate(
                    derivationIndex: 303,
                    remoteState: .inRecycler(.init(index: 4, membersCount: 21))
                )]
            }, { [] }).asyncExecute()

            let result = try await stored(original)
            #expect(result.recyclerFungibility == 61)
            #expect(result.maxRecyclerFungibility == 77)
        }

        @Test("updates remoteState only, preserves other fields")
        func updatesLocationOnly() async throws {
            let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
            let original = Voucher(
                exponent: 11,
                derivationIndex: 100,
                allocatedAt: now,
                readyAt: now.addingTimeInterval(2_400),
                remoteState: .unlocated,
                publicKey: Data(repeating: 0x64, count: 32)
            )
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            let updated = VoucherLocationUpdate(
                derivationIndex: 100,
                remoteState: .inRecycler(.init(index: 3, membersCount: 0))
            )

            try await locationRepo.saveOperation({ [updated] }, { [] }).asyncExecute()

            let result = try #require(
                try await fullRepo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            guard case let .inRecycler(recycler) = result.remoteState else {
                Issue.record("Expected .inRecycler, got \(result.remoteState)")
                return
            }
            #expect(recycler.index == 3)
            #expect(result.exponent == 11)
            #expect(result.derivationIndex == 100)
            #expect(result.allocatedAt == now)
            #expect(result.readyAt == now.addingTimeInterval(2_400))
        }

        @Test("throws missingVoucher when entity does not exist")
        func throwsForNewEntity() async throws {
            let update = VoucherLocationUpdate(
                derivationIndex: 999,
                remoteState: .onboarding
            )

            await #expect(throws: VoucherLocationMapper.MappingError.missingVoucher) {
                try await locationRepo.saveOperation({ [update] }, { [] }).asyncExecute()
            }
        }
    }
}
