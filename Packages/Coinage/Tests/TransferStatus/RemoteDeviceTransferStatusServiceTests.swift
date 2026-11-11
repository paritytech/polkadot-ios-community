import DurableTransactionsTestSupport
import Foundation
import NovaCrypto
import Testing
@testable import Coinage

@Suite("Remote transfer status follows the finalized chain", .timeLimit(.minutes(1)))
struct RemoteDeviceTransferStatusServiceTests {
    private let chain = CoinageFakeChain(initialState: .empty)
    private let chainFactory: FakePinnedChainViewFactory<CoinageChainState>
    private let coinQuery = StubCoinOnChainQuery()
    private let service: RemoteDeviceTransferStatusService
    private let secret: Data
    private let publicKey: PublicKey

    init() throws {
        chain.produceBlock()
        chain.produceBlock()
        chain.finalize(upTo: 1)
        chainFactory = FakePinnedChainViewFactory(chain: chain)

        let keypair = try SNKeyFactory().createKeypair(fromSeed: Data(repeating: 0xCD, count: 32))
        secret = keypair.privateKey().rawData()
        publicKey = keypair.publicKey().rawData()

        service = RemoteDeviceTransferStatusService(
            chainViewFactory: chainFactory,
            chainId: "status-chain",
            coinOnChainQuery: coinQuery,
            snKeyFactory: SNKeyFactory(),
            logger: nil
        )
    }

    @Test("a coin is not seen, then on chain with its exponent, then gone once it leaves the finalized chain")
    func coinGoesThroughSeenAndGone() async throws {
        var iterator = service.subscribeStatuses(coinKeys: [secret]).makeAsyncIterator()
        #expect(try await iterator.next()?[publicKey] == .notSeen)

        coinQuery.setPresent(publicKey, atBlockHash: chain.finalizedHead.hash, value: 3)
        chainFactory.emitFinalizedHead(1)
        #expect(try await iterator.next()?[publicKey] == .onChain(exponent: 3))

        chain.finalize(upTo: 2)
        chainFactory.emitFinalizedHead(2)
        #expect(try await iterator.next()?[publicKey] == .gone(exponent: 3))
    }

    @Test("a head that can't be read is skipped and the stream goes on")
    func unreadableHeadIsSkipped() async throws {
        coinQuery.setPresent(publicKey, atBlockHash: chain.finalizedHead.hash, value: 1)
        var iterator = service.subscribeStatuses(coinKeys: [secret]).makeAsyncIterator()
        #expect(try await iterator.next()?[publicKey] == .onChain(exponent: 1))

        coinQuery.failNextRead()
        chainFactory.emitFinalizedHead(1)
        chain.finalize(upTo: 2)
        chainFactory.emitFinalizedHead(2)

        #expect(try await iterator.next()?[publicKey] == .gone(exponent: 1))
    }

    @Test("no coins to watch is a finished stream")
    func emptyKeySetFinishes() async throws {
        var emissions = 0
        for try await _ in service.subscribeStatuses(coinKeys: []) {
            emissions += 1
        }
        #expect(emissions == 0)
    }
}
