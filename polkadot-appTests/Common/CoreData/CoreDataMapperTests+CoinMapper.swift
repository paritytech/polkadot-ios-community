import BigInt
import Coinage
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("CoinMapper")
    struct CoinMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var repo: AnyDataProviderRepository<Coin> { facade.makeRepo(mapper: CoinMapper()) }

        @Test("roundTrip preserves all fields")
        func roundTrip() async throws {
            let original = Coin(exponent: 12, derivationIndex: 42, age: 5, state: .available)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.exponent == original.exponent)
            #expect(result.derivationIndex == original.derivationIndex)
            #expect(result.age == original.age)
            #expect(result.state == original.state)
        }

        @Test("nil age stored as -1 and restored to nil")
        func nilAgeRestoredToNil() async throws {
            let original = Coin(exponent: 8, derivationIndex: 100, age: nil, state: .spent)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.age == nil)
        }

        @Test("state .spent round-trips")
        func stateSpent() async throws {
            let original = Coin(exponent: 6, derivationIndex: 10, age: nil, state: .spent)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()
            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.state == .spent)
        }

        @Test("state .available round-trips")
        func stateAvailable() async throws {
            let original = Coin(exponent: 6, derivationIndex: 11, age: nil, state: .available)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()
            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.state == .available)
        }

        @Test("state .recycling round-trips")
        func stateRecycling() async throws {
            let original = Coin(exponent: 6, derivationIndex: 12, age: nil, state: .recycling)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()
            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.state == .recycling)
        }

        @Test("state .pendingTransfer round-trips")
        func statePendingTransfer() async throws {
            let original = Coin(exponent: 6, derivationIndex: 13, age: nil, state: .pendingTransfer)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()
            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.state == .pendingTransfer)
        }
    }
}
