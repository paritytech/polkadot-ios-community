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

        @Test("Ring growth preserves the first confirmed inclusion and other voucher fields")
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
                remoteState: .inRecycler(.init(index: 3, membersCount: 31, enteredAt: now))
            )

            try await locationRepo.saveOperation({ [updated] }, { [] }).asyncExecute()

            let later = VoucherLocationUpdate(
                derivationIndex: 100,
                remoteState: .inRecycler(.init(index: 3, membersCount: 32, enteredAt: now.addingTimeInterval(600)))
            )
            try await locationRepo.saveOperation({ [later] }, { [] }).asyncExecute()

            let result = try #require(
                try await fullRepo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result == original.adjusting(state: .inRecycler(.init(index: 3, membersCount: 32, enteredAt: now))))
        }

        @Test("Moving rings and restoring restart the inclusion timer")
        func movingAndRestoringRestartTimer() async throws {
            let first = Date(timeIntervalSince1970: 1_000)
            let later = first.addingTimeInterval(600)
            let original = Voucher(
                exponent: 1,
                derivationIndex: 0,
                allocatedAt: first,
                readyAt: first,
                remoteState: .inRecycler(.init(index: 1, membersCount: 32, enteredAt: first)),
                publicKey: Data(repeating: 0, count: 32)
            )
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()
            let moved = VoucherLocationUpdate(
                derivationIndex: 0,
                remoteState: .inRecycler(.init(index: 2, membersCount: 32, enteredAt: later))
            )
            try await locationRepo.saveOperation({ [moved] }, { [] }).asyncExecute()
            let afterMove = try await fullRepo.fetchOperation(by: { original.identifier }, options: .init())
                .asyncExecute()
            #expect(afterMove == original.adjusting(state: moved.remoteState))

            let restored = original.adjusting(state: .inRecycler(.init(index: 2, membersCount: 0)))
            try await fullRepo.saveOperation({ [restored] }, { [] }).asyncExecute()
            let afterRestore = try await fullRepo.fetchOperation(by: { original.identifier }, options: .init())
                .asyncExecute()
            #expect(afterRestore == restored)

            let confirmed = VoucherLocationUpdate(
                derivationIndex: 0,
                remoteState: .inRecycler(.init(index: 2, membersCount: 32, enteredAt: later.addingTimeInterval(600)))
            )
            try await locationRepo.saveOperation({ [confirmed] }, { [] }).asyncExecute()
            let afterConfirmation = try await fullRepo.fetchOperation(by: { original.identifier }, options: .init())
                .asyncExecute()
            #expect(afterConfirmation == original.adjusting(state: confirmed.remoteState))
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
