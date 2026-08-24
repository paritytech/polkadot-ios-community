import Coinage
import Foundation

extension BlockRef {
    /// Block `number` with a hash derived from it, so distinct numbers stay distinguishable.
    static func fixture(_ number: UInt32) -> BlockRef {
        BlockRef(number: number, hash: Data([UInt8(truncatingIfNeeded: number)]))
    }
}

extension DurabilityEntry {
    /// A pending entry checkpointed at block 100 with a 60-block window — the baseline the
    /// durability suites vary from.
    static func fixture(
        id: TransactionId = UUID(),
        inputs: [Input] = [],
        outputs: [OwnAsset] = [],
        checkpoint: BlockRef = .fixture(100),
        status: EntryStatus = .pending
    ) -> DurabilityEntry {
        DurabilityEntry(
            id: id,
            inputs: inputs,
            outputs: outputs,
            checkpoint: checkpoint,
            mortality: 60,
            status: status
        )
    }
}
