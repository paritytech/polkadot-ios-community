import Foundation
import Coinage

actor MockDurabilityStore: DurabilityStoring {
    private var entries: [TransactionId: DurabilityEntry] = [:]
    private var marks: Set<String> = []
    private var nextSequence: Int64 = 1

    var allEntries: [DurabilityEntry] {
        sortedEntries
    }

    var handoffIdentifiers: Set<String> {
        marks
    }

    func register(_ entry: DurabilityEntry) async throws {
        let inputIds = Set(entry.inputs.map(\.identifier))
        let outputIds = Set(entry.outputs.map(\.identifier))

        let claimedInputs = Set(
            entries.values
                .filter { $0.status != .failure }
                .flatMap { $0.inputs.map(\.identifier) }
        )
        let mintedOutputs = Set(entries.values.flatMap { $0.outputs.map(\.identifier) })
        let receivedInputs = Set(
            entries.values.flatMap(\.inputs).compactMap { input -> String? in
                guard case .coin(.received) = input else { return nil }
                return input.identifier
            }
        )

        try RegistrationValidator.validate(
            entry,
            claimedInputs: claimedInputs,
            mintedOutputs: mintedOutputs,
            receivedInputs: receivedInputs,
            marks: marks
        )

        var sequenced = entry
        sequenced.sequence = nextSequence
        entries[entry.id] = sequenced
        nextSequence += 1
    }

    func updateStatus(_ id: TransactionId, to status: EntryStatus) async throws {
        try mutate(id) { $0.status = status }
    }

    func recordSuccessDetected(_ id: TransactionId, at block: BlockRef?) async throws {
        try mutate(id) { $0.successDetectedAt = block }
    }

    func recordTxHash(_ id: TransactionId, txHash: Data) async throws {
        try mutate(id) { $0.txHash = txHash }
    }

    func fetchLive() async throws -> [DurabilityEntry] {
        sortedEntries.filter(\.status.isLive)
    }

    func fetchAll() async throws -> [DurabilityEntry] {
        sortedEntries
    }

    func fetch(id: TransactionId) async throws -> DurabilityEntry? {
        entries[id]
    }

    func minter(of asset: OwnAsset) async throws -> DurabilityEntry? {
        entries.values.first { $0.outputs.contains(asset) }
    }

    func consumers(of input: DurabilityInput) async throws -> [DurabilityEntry] {
        sortedEntries.filter { $0.inputs.contains(input) }
    }

    func markHandedOff(_ asset: OwnAsset) async throws {
        marks.insert(asset.identifier)
    }

    func hasEverBeenHandedOff(_ asset: OwnAsset) async throws -> Bool {
        marks.contains(asset.identifier)
    }

    func handedOffCoins() async throws -> [OwnAsset] {
        marks.compactMap { identifier in
            let parts = identifier.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let index = UInt32(parts[1]) else { return nil }

            switch parts[0] {
            case "coin": return .coin(index)
            case "voucher": return .recyclerVoucher(index)
            default: return nil
            }
        }
    }
}

private extension MockDurabilityStore {
    var sortedEntries: [DurabilityEntry] {
        entries.values.sorted { $0.sequence < $1.sequence }
    }

    func mutate(_ id: TransactionId, _ change: (inout DurabilityEntry) -> Void) throws {
        guard var entry = entries[id] else {
            throw DurabilityError.entryNotFound(id)
        }
        change(&entry)
        entries[id] = entry
    }
}
