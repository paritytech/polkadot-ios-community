import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import Keystore_iOS
@testable import Coinage

struct CoinAllocatorTests {
    private let keychain: InMemoryKeychain
    private let store: CoinIndexstore
    private let allocator: CoinAllocator

    init() {
        let keychain = InMemoryKeychain()
        let store = CoinIndexstore(storage: keychain)

        self.keychain = keychain
        self.store = store
        allocator = CoinAllocator(storage: store)
    }

    @Test("Successfully allocates a coin")
    func allocateCoin() async throws {
        let expectedIndex: UInt32 = 42
        let seedIndex: UInt32 = 41
        try keychain.saveKey(seedIndex.scaleEncoded(), with: store.storageKey)

        let exponent: Int16 = 5

        let coin = try await allocator.allocate(exponent: exponent)

        #expect(coin.derivationIndex == expectedIndex)
        #expect(coin.exponent == exponent)
        #expect(coin.age == nil)
        #expect(coin.state == .available)
    }

    @Test("Propagates errors from storage")
    func storageFailure() async throws {
        try keychain.saveKey(Data("".utf8), with: store.storageKey)

        await #expect(throws: Error.self) {
            try await allocator.allocate(exponent: 0)
        }
    }
}
