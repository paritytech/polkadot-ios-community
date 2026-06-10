import Coinage
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("TransferWALMapper")
    struct TransferWALMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var repo: AnyDataProviderRepository<TransferWALEntry> { facade.makeRepo(mapper: TransferWALMapper()) }

        private func makeEntry(
            id: UUID = UUID(),
            inputCoinIds: [String] = ["1", "2"],
            inputVoucherIds: [String] = [],
            expectedCoinIndices: [UInt32] = [0, 1],
            checkpointBlock: CheckpointBlock = .pending,
            mortality: UInt32 = 64,
            createdAt: Date = Date(timeIntervalSince1970: 1_000_000)
        ) -> TransferWALEntry {
            TransferWALEntry(
                id: id,
                inputCoinIds: inputCoinIds,
                inputVoucherIds: inputVoucherIds,
                expectedCoinIndices: expectedCoinIndices,
                checkpointBlock: checkpointBlock,
                mortality: mortality,
                createdAt: createdAt
            )
        }

        @Test("coin ids round-trip all fields")
        func roundTripWithCoinIds() async throws {
            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            let original = makeEntry(
                inputCoinIds: ["1", "2"],
                inputVoucherIds: [],
                expectedCoinIndices: [2, 3],
                mortality: 128,
                createdAt: createdAt
            )
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.id == original.id)
            #expect(result.inputCoinIds == ["1", "2"])
            #expect(result.inputVoucherIds == [])
            #expect(result.expectedCoinIndices == [2, 3])
            #expect(result.mortality == 128)
            #expect(result.createdAt == createdAt)
        }

        @Test("voucher ids round-trip all fields")
        func roundTripWithVoucherIds() async throws {
            let original = makeEntry(
                inputCoinIds: [],
                inputVoucherIds: ["10", "11", "12"],
                expectedCoinIndices: [10, 11, 12]
            )
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.inputCoinIds == [])
            #expect(result.inputVoucherIds == ["10", "11", "12"])
            #expect(result.expectedCoinIndices == [10, 11, 12])
        }

        @Test("checkpointBlock .pending round-trips")
        func checkpointBlockPending() async throws {
            let original = makeEntry(checkpointBlock: .pending)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.checkpointBlock == .pending)
        }

        @Test("checkpointBlock .known preserves number and hash")
        func checkpointBlockKnown() async throws {
            let hash = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])
            let original = makeEntry(checkpointBlock: .known(number: 1_234_567, hash: hash))
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.checkpointBlock == .known(number: 1_234_567, hash: hash))
        }

        @Test("empty coin and voucher arrays round-trip")
        func emptyArrays() async throws {
            let original = makeEntry(
                inputCoinIds: [],
                inputVoucherIds: [],
                expectedCoinIndices: []
            )
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.inputCoinIds.isEmpty)
            #expect(result.inputVoucherIds.isEmpty)
            #expect(result.expectedCoinIndices.isEmpty)
        }

        @Test("UInt32 overflow values preserved via bitPattern")
        func uint32OverflowPreserved() async throws {
            let original = makeEntry(
                expectedCoinIndices: [UInt32.max, 0, UInt32.max / 2],
                mortality: UInt32.max
            )
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.expectedCoinIndices == [UInt32.max, 0, UInt32.max / 2])
            #expect(result.mortality == UInt32.max)
        }
    }

    // MARK: - TransferWALUpdateMapper

    @Suite("TransferWALUpdateMapper")
    struct TransferWALUpdateMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var fullRepo: AnyDataProviderRepository<TransferWALEntry> {
            facade.makeRepo(mapper: TransferWALMapper())
        }

        private var updateRepo: AnyDataProviderRepository<TransferWALEntry> {
            facade.makeRepo(mapper: TransferWALUpdateMapper())
        }

        @Test("updates checkpointBlock, preserves other fields")
        func updatesBlockOnly() async throws {
            let id = UUID()
            let original = TransferWALEntry(
                id: id,
                inputCoinIds: ["1", "2"],
                inputVoucherIds: ["3"],
                expectedCoinIndices: [5, 6, 7],
                checkpointBlock: .pending,
                mortality: 256,
                createdAt: Date(timeIntervalSince1970: 1_000_000)
            )
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            let blockHash = Data([0x01, 0x02, 0x03])
            let stub = TransferWALEntry(
                id: id,
                inputCoinIds: [],
                inputVoucherIds: [],
                expectedCoinIndices: [],
                checkpointBlock: .known(number: 99, hash: blockHash),
                mortality: 0,
                createdAt: .distantPast
            )
            try await updateRepo.saveOperation({ [stub] }, { [] }).asyncExecute()

            let result = try #require(
                try await fullRepo.fetchOperation(by: { id.uuidString }, options: .init()).asyncExecute()
            )
            #expect(result.checkpointBlock == .known(number: 99, hash: blockHash))
            // Fields not touched by update mapper must be unchanged
            #expect(result.inputCoinIds == ["1", "2"])
            #expect(result.inputVoucherIds == ["3"])
            #expect(result.expectedCoinIndices == [5, 6, 7])
            #expect(result.mortality == 256)
        }

        @Test("resets to pending on subsequent update")
        func updateToPending() async throws {
            let id = UUID()
            let blockHash = Data([0xAA, 0xBB])
            let original = TransferWALEntry(
                id: id,
                inputCoinIds: ["c1"],
                inputVoucherIds: [],
                expectedCoinIndices: [0],
                checkpointBlock: .known(number: 50, hash: blockHash),
                mortality: 64,
                createdAt: Date(timeIntervalSince1970: 500_000)
            )
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            let stub = TransferWALEntry(
                id: id,
                inputCoinIds: [],
                inputVoucherIds: [],
                expectedCoinIndices: [],
                checkpointBlock: .pending,
                mortality: 0,
                createdAt: .distantPast
            )
            try await updateRepo.saveOperation({ [stub] }, { [] }).asyncExecute()

            let result = try #require(
                try await fullRepo.fetchOperation(by: { id.uuidString }, options: .init()).asyncExecute()
            )
            #expect(result.checkpointBlock == .pending)
        }

        @Test("throws noExistingEntity for unsaved entry")
        func throwsForNewEntity() async throws {
            let stub = TransferWALEntry(
                id: UUID(),
                inputCoinIds: [],
                inputVoucherIds: [],
                expectedCoinIndices: [],
                checkpointBlock: .pending,
                mortality: 0,
                createdAt: .distantPast
            )

            await #expect(throws: TransferWALUpdateMapper.MappingError.noExistingEntity) {
                try await updateRepo.saveOperation({ [stub] }, { [] }).asyncExecute()
            }
        }
    }
}
