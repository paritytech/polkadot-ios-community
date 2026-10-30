import DurableTransactions
import Foundation
import NovaCrypto
import SubstrateSdk
import Testing
@testable import Coinage

@Suite("Reclaim Coins Service")
struct ReclaimCoinsServiceTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let group: CoinageTxGroupId = "message-1"
    private let snKeyFactory = SNKeyFactory()

    @Test("only committed, on-chain and unconsumed coins are reclaimed")
    func reclaimsOnlyEligibleCoins() async throws {
        let eligible = try makeCoin(seed: 1, index: 1, handoff: .committed, onChain: true)
        let notOnChain = try makeCoin(seed: 2, index: 2, handoff: .committed, onChain: false)
        let consumed = try makeCoin(seed: 3, index: 3, handoff: .committed, onChain: true, consumer: .pendingSuccess)
        let neverHandedOff = try makeCoin(seed: 4, index: 4, handoff: .none, onChain: true)
        let all = [eligible, notOnChain, consumed, neverHandedOff]
        let harness = makeHarness(tracked: all)

        try await harness.sut.reclaim(coinKeys: all.map(\.secret), groupId: group)

        let requests = harness.txService.scheduledRequests
        #expect(requests.count == 1)
        #expect(requests.first?.inputs == [.coin(.reclaimed(1, eligible.publicKey))])
    }

    @Test("a reclaim mints its destination at the reclaimed coin's exponent")
    func destinationKeepsExponent() async throws {
        let coin = try makeCoin(seed: 1, index: 1, handoff: .committed, onChain: true, exponent: 5)
        let harness = makeHarness(tracked: [coin])

        try await harness.sut.reclaim(coinKeys: [coin.secret], groupId: group)

        let minted = await harness.allocator.mintedCoins
        #expect(minted.map(\.exponent) == [5])
        #expect(harness.txService.scheduledRequests.first?.outputs == minted.map {
            OwnAsset.coin($0.derivationIndex, $0.publicKey)
        })
    }

    @Test("the destination adds one transfer hop of the bundle size and keeps the parent's chain")
    func destinationProvenance() async throws {
        let first = try makeCoin(seed: 1, index: 1, handoff: .committed, onChain: true, hops: [.split(fanout: 2)])
        let second = try makeCoin(seed: 2, index: 2, handoff: .committed, onChain: true, hops: [.split(fanout: 2)])
        let harness = makeHarness(tracked: [first, second])

        try await harness.sut.reclaim(coinKeys: [first.secret, second.secret], groupId: group)

        let minted = await harness.allocator.mintedCoins
        #expect(minted.count == 2)
        #expect(minted.allSatisfy { $0.hops == [.split(fanout: 2), .transfer(bundleSize: 2)] })
        #expect(minted.allSatisfy { $0.recyclerFungibility == first.coin.recyclerFungibility })
    }

    @Test("the reclaim is scheduled under the reclaim policy and retried until its window closes")
    func policyWindow() async throws {
        let coin = try makeCoin(seed: 1, index: 1, handoff: .committed, onChain: true)
        let harness = makeHarness(tracked: [coin])

        try await harness.sut.reclaim(coinKeys: [coin.secret], groupId: group)

        let policy = try #require(harness.txService.scheduledRequests.first?.policy)
        #expect(policy.id == CoinageSubmissionParams.reclaimPolicyId)
        let params = try CoinageSubmissionParams.decodeTransfer(policy.params)
        #expect(params.buildUntil == now.addingTimeInterval(CoinageConstants.reclaimRetryWindow))
        #expect(params.retryFailures)
    }

    @Test("the reclaims are scheduled under the group they were asked for")
    func groupIdPassesThrough() async throws {
        let coin = try makeCoin(seed: 1, index: 1, handoff: .committed, onChain: true)
        let harness = makeHarness(tracked: [coin])

        try await harness.sut.reclaim(coinKeys: [coin.secret], groupId: group)

        #expect(harness.txService.scheduledGroupIds == [group])
    }

    @Test("nothing reclaimable schedules nothing")
    func nothingEligibleSchedulesNothing() async throws {
        let coin = try makeCoin(seed: 1, index: 1, handoff: .committed, onChain: false)
        let harness = makeHarness(tracked: [coin])

        try await harness.sut.reclaim(coinKeys: [coin.secret], groupId: group)

        #expect(harness.txService.scheduledRequests.isEmpty)
        #expect(await harness.allocator.mintedCoins.isEmpty)
    }

    @Test("a failed reclaim is reported until a later attempt for its coin supersedes it")
    func failedReclaimsAreReportedUntilSuperseded() async throws {
        let store = MockCoinageTxRepository()
        try await store.markHandedOff(.coin(1, keyA))
        try await store.markHandedOff(.coin(2, keyB))
        try await store.register(entry(.coin(.reclaimed(1, keyA)), status: .failure))
        try await store.register(entry(.coin(.reclaimed(2, keyB)), status: .failure))
        try await store.register(entry(.coin(.reclaimed(2, keyB)), status: .pending))
        let sut = makeHarness(tracked: [], store: store).sut

        var updates = sut.subscribeFailedReclaims(groupId: group).makeAsyncIterator()
        #expect(try await updates.next() == Set([keyA]))

        try await store.register(entry(.coin(.reclaimed(1, keyA)), status: .pending))
        #expect(try await updates.next() == Set<PublicKey>())
    }
}

private extension ReclaimCoinsServiceTests {
    struct FakeCoin {
        let secret: Data
        let publicKey: PublicKey
        let tracked: TrackedCoin

        var coin: Coin { tracked.coin }
    }

    struct Harness {
        let sut: ReclaimCoinsService
        let txService: MockCoinageTxService
        let allocator: MockCoinAllocator
    }

    var keyA: PublicKey { Data(repeating: 1, count: 32) }
    var keyB: PublicKey { Data(repeating: 2, count: 32) }

    func makeCoin(
        seed: UInt8,
        index: CoinageKeyIndex,
        handoff: CoinHandoffMark,
        onChain: Bool,
        exponent: Int16 = 3,
        hops: [Hop] = [],
        consumer: CoinageTxStatus? = nil
    ) throws -> FakeCoin {
        let secret = try snKeyFactory.createKeypair(fromSeed: Data(repeating: seed, count: 32)).privateKey().rawData()
        let publicKey = try snKeyFactory.createPublicKey(fromSecret: secret).rawData()
        let coin = Coin(
            exponent: exponent,
            derivationIndex: index,
            age: 1,
            isOnchain: onChain,
            handoffMark: handoff,
            recyclerFungibility: 80,
            hops: hops,
            publicKey: publicKey
        )
        let state = CoinageAssetState(
            handedOff: handoff == .committed,
            consumerStatus: consumer,
            minterStatus: .finalizedSuccess
        )
        return FakeCoin(secret: secret, publicKey: publicKey, tracked: TrackedCoin(coin: coin, state: state))
    }

    func makeHarness(tracked: [FakeCoin], store: MockCoinageTxRepository = MockCoinageTxRepository()) -> Harness {
        let databaseFactory = StubDatabaseDependencyFactory()
        databaseFactory.trackedCoins.send(tracked.map(\.tracked))

        let txService = MockCoinageTxService(store: store)
        let allocator = MockCoinAllocator()
        let sut = ReclaimCoinsService(
            txService: txService,
            databaseFactory: databaseFactory,
            minter: allocator,
            snKeyFactory: snKeyFactory,
            dateProvider: StubDateProvider(now),
            logger: nil
        )

        return Harness(sut: sut, txService: txService, allocator: allocator)
    }

    func entry(_ input: CoinageTxInput, status: CoinageTxStatus) -> CoinageTxEntry {
        CoinageTxEntry(
            inputs: [input],
            outputs: [],
            groupId: group,
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 0, hash: Data(repeating: 0, count: 32)),
            mortality: 300,
            status: status
        )
    }
}
