import Coinage
import Foundation
import Testing

@testable import polkadot_app

@Suite("Coinage installation repository")
struct CoinageInstallationRepositoryTests {
    private let repository = CoinageInstallationCoreDataRepository(storageFacade: UserDataStorageTestFacade())

    @Test("the current installation is created once and read back afterwards")
    func idempotentCurrent() async throws {
        let first = try await repository.getOrCreateCurrent()
        let second = try await repository.getOrCreateCurrent()

        let previous = try await repository.getPrevious()
        #expect(first == second)
        #expect(previous.isEmpty)
    }

    @Test("concurrent first callers all get the same current installation")
    func concurrentCurrent() async throws {
        let ids = try await withThrowingTaskGroup(of: CoinageInstallationId.self) { group in
            for _ in 0 ..< 16 {
                group.addTask { try await repository.getOrCreateCurrent() }
            }
            return try await group.reduce(into: Set<CoinageInstallationId>()) { $0.insert($1) }
        }

        #expect(ids.count == 1)
    }

    @Test("previous installations skip the current one and repeats")
    func addPrevious() async throws {
        let current = try await repository.getOrCreateCurrent()

        try await repository.addPrevious([current, .other, .other])
        try await repository.addPrevious([.other, .fixed(0x22)])

        let previous = try await repository.getPrevious()
        #expect(Set(previous.map(\.id)) == [.other, .fixed(0x22)])
        #expect(previous.allSatisfy { !$0.initialScanCompleted })
        #expect(previous.allSatisfy { $0.coinScanNextIndex == 0 && $0.voucherScanNextIndex == 0 })
    }

    @Test("scan cursors and the completion flag are persisted per installation")
    func cursors() async throws {
        try await repository.addPrevious([.other, .fixed(0x22)])

        try await repository.updateCoinScanNextIndex(1_500, for: .other)
        try await repository.updateVoucherScanNextIndex(2_000, for: .other)
        try await repository.markInitialScanCompleted(.other)

        let previous = try await repository.getPrevious()
        let updated = try #require(previous.first { $0.id == .other })
        let untouched = try #require(previous.first { $0.id == .fixed(0x22) })

        #expect(updated.coinScanNextIndex == 1_500)
        #expect(updated.voucherScanNextIndex == 2_000)
        #expect(updated.initialScanCompleted)
        #expect(untouched.coinScanNextIndex == 0)
        #expect(!untouched.initialScanCompleted)
    }

    @Test("an update for an unknown installation fails")
    func unknownInstallation() async throws {
        await #expect(throws: CoinageInstallationRepositoryError.self) {
            try await repository.markInitialScanCompleted(.other)
        }
    }
}
