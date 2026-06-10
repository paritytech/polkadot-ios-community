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
        private var locationRepo: AnyDataProviderRepository<Voucher> { facade.makeRepo(mapper: VoucherLocationMapper())
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
                localState: .available
            )
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            let updated = original.adjusting(state: .inRecycler(.init(index: 3)))
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
            #expect(result.localState == .available)
        }

        @Test("throws noExistingRequest when entity does not exist")
        func throwsForNewEntity() async throws {
            let now = Date(timeIntervalSinceReferenceDate: 3_000_000)
            let voucher = Voucher(
                exponent: 13,
                derivationIndex: 999,
                allocatedAt: now,
                readyAt: now.addingTimeInterval(1_000),
                remoteState: .onboarding,
                localState: .available
            )

            await #expect(throws: VoucherLocationMapper.MappingError.noExistingRequest) {
                try await locationRepo.saveOperation({ [voucher] }, { [] }).asyncExecute()
            }
        }
    }
}
