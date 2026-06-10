import BigInt
import Coinage
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("CoinStateMapper")
    struct CoinStateMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var fullRepo: AnyDataProviderRepository<Coin> { facade.makeRepo(mapper: CoinMapper()) }
        private var stateRepo: AnyDataProviderRepository<Coin> { facade.makeRepo(mapper: CoinStateMapper()) }

        @Test("updates state only, preserves other fields")
        func updatesStateOnly() async throws {
            let original = Coin(exponent: 15, derivationIndex: 200, age: 7, state: .available)
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            let updated = original.changing(state: .spent)
            try await stateRepo.saveOperation({ [updated] }, { [] }).asyncExecute()

            let result = try #require(
                try await fullRepo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.state == .spent)
            #expect(result.exponent == 15)
            #expect(result.derivationIndex == 200)
            #expect(result.age == 7)
        }
    }
}
