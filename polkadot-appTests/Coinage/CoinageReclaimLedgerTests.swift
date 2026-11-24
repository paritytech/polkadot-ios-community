import Coinage
import DurableTransactions
import Foundation
import Testing

@testable import polkadot_app

@Suite("Coinage reclaim ledger")
struct CoinageReclaimLedgerTests {
    @Test("a reclaimed input of a handed-off coin reads back as reclaimed")
    func reclaimedInputReadsBackAsReclaimed() async throws {
        let world = try await CoinageLedgerWorld()
        try await world.precommit([world.coin(1)])
        let reclaimed = CoinageTxInput.coin(.reclaimed(CoinageLedgerWorld.keyIndex(1), CoinageLedgerWorld.coinKey(1)))

        try await world.ledger.register([registration(inputs: [reclaimed], groupId: world.messageId)])

        let entry = try #require(try await world.scheduledEntries().first)
        #expect(entry.inputs == [reclaimed])
    }

    @Test("an own input reads back as own")
    func ownInputReadsBackAsOwn() async throws {
        let world = try await CoinageLedgerWorld()
        let coin = world.coin(1)

        try await world.ledger.register([registration(inputs: [coin.asInput], groupId: world.messageId)])

        let entry = try #require(try await world.scheduledEntries().first)
        #expect(entry.inputs == [coin.asInput])
    }
}

private extension CoinageReclaimLedgerTests {
    func registration(inputs: [CoinageTxInput], groupId: CoinageTxGroupId) -> CoinageTxRegistration {
        CoinageTxRegistration(
            txHash: Data(repeating: 0x01, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortalityBlocks: 64,
            groupId: groupId,
            inputs: inputs,
            outputs: []
        )
    }
}
