import Coinage
import DurableTransactions
import Foundation
import Testing

@testable import polkadot_app

/// The reclaim input as the CoreData ledger stores it: a link to our own coin row, with no marker of its
/// own, so reading it back reports the same own input the coin was minted under.
@Suite("Coinage reclaim ledger")
struct CoinageReclaimLedgerTests {
    @Test("a reclaimed input of a handed-off coin reads back as that coin's own input")
    func reclaimedInputReadsBackAsOwn() async throws {
        let world = try await CoinageLedgerWorld()
        let coin = world.coin(1)
        try await world.precommit([coin])

        let registration = CoinageTxRegistration(
            txHash: Data(repeating: 0x01, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortalityBlocks: 64,
            groupId: world.messageId,
            inputs: [.coin(.reclaimed(CoinageLedgerWorld.keyIndex(1), CoinageLedgerWorld.coinKey(1)))],
            outputs: []
        )
        try await world.ledger.register([registration])

        let entry = try #require(try await world.scheduledEntries().first)
        #expect(entry.inputs == [coin.asInput])
    }
}
