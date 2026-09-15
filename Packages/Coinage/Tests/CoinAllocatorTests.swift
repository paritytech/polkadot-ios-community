import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import Operation_iOS
@testable import Coinage

struct CoinAllocatorTests {
    private let queries = StubKeyIndexQueries()
    private let allocator: CoinAllocator

    init() {
        allocator = CoinAllocator(
            installationRepository: InMemoryInstallations(current: .test),
            keyIndexQueries: queries,
            coinRepository: AnyDataProviderRepository(StubRepository<Coin>()),
            keyFactory: CoinKeypairFactory(entropyManager: MockEntropyManager(entropy: Data(
                repeating: 0x01,
                count: 32
            )))
        )
    }

    @Test("an allocated coin takes the next index of the current installation")
    func allocateCoin() async throws {
        queries.maxCoinItem = 41

        let coin = try await allocator.allocate(exponent: 5, provenance: .unloaded(recyclerFungibility: 73))

        #expect(coin.derivationIndex == CoinageKeyIndex(installation: .test, item: 42))
        #expect(queries.coinQueries == [.test])
        #expect(coin.exponent == 5)
        #expect(coin.age == nil)
        #expect(coin.recyclerFungibility == 73)
        #expect(coin.hops.isEmpty)
    }

    @Test("an installation with no coins yet starts at item zero")
    func firstItem() async throws {
        queries.maxCoinItem = nil

        let coin = try await allocator.allocate(exponent: 2, provenance: .unknown)

        #expect(coin.derivationIndex == CoinageKeyIndex(installation: .test, item: 0))
    }

    @Test("persists the provenance it was minted with")
    func allocateCoinWithProvenance() async throws {
        let hops: [Hop] = [.transfer(bundleSize: 3), .split(fanout: 4)]
        let coin = try await allocator.allocate(
            exponent: 2,
            provenance: CoinProvenance(recyclerFungibility: nil, hops: hops)
        )

        #expect(coin.recyclerFungibility == nil)
        #expect(coin.hops == hops)
    }

    @Test("propagates errors from the index query")
    func queryFailure() async throws {
        queries.error = InstallationStubError.unreachable

        await #expect(throws: InstallationStubError.unreachable) {
            try await allocator.allocate(exponent: 0, provenance: .unknown)
        }
    }
}

/// The highest stored item per installation, as the allocators would read it from the store.
final class StubKeyIndexQueries: CoinageKeyIndexQuerying, @unchecked Sendable {
    var maxCoinItem: UInt32?
    var maxVoucherItem: UInt32?
    var error: Error?
    private(set) var coinQueries: [CoinageInstallationId] = []
    private(set) var voucherQueries: [CoinageInstallationId] = []

    func maxCoinItem(in installation: CoinageInstallationId) async throws -> UInt32? {
        coinQueries.append(installation)
        if let error { throw error }
        return maxCoinItem
    }

    func maxVoucherItem(in installation: CoinageInstallationId) async throws -> UInt32? {
        voucherQueries.append(installation)
        if let error { throw error }
        return maxVoucherItem
    }
}
