import AsyncExtensions
import Foundation
@testable import Coinage

actor MockDurabilityStore: DurabilityStoring {
    private var entries: [TransactionId: DurabilityEntry] = [:]
    private var pendingMarks: Set<String> = []
    private var committedMarks: Set<String> = []
    private var nextSequence: Int64 = 1
    private var statusObservers: [TransactionId: [AsyncStream<EntryStatus>.Continuation]] = [:]

    var allEntries: [DurabilityEntry] {
        sortedEntries
    }

    var handoffIdentifiers: Set<String> {
        pendingMarks.union(committedMarks)
    }

    func register(_ entry: DurabilityEntry) async throws {
        guard !entry.inputs.isEmpty || !entry.outputs.isEmpty else {
            throw DurabilityError.emptyEntry
        }

        let mintedOutputs = Set(entries.values.flatMap { $0.outputs.map(\.identifier) })
        if let duplicate = entry.outputs.first(where: { mintedOutputs.contains($0.identifier) }) {
            throw DurabilityError.outputNotFresh(duplicate.identifier)
        }

        let claimedInputs = Set(
            entries.values
                .filter { $0.status != .failure }
                .flatMap { $0.inputs.map(\.identifier) }
        )
        if let claimed = entry.inputs.first(where: { claimedInputs.contains($0.identifier) }) {
            throw DurabilityError.inputAlreadyClaimed(claimed.identifier)
        }

        let marks = handoffIdentifiers
        if let marked = entry.inputs.first(where: { marks.contains($0.identifier) }) {
            throw DurabilityError.inputHandedOff(marked.identifier)
        }

        var sequenced = entry
        sequenced.sequence = nextSequence
        entries[entry.id] = sequenced
        nextSequence += 1
    }

    func updateStatus(_ id: TransactionId, to status: EntryStatus) async throws {
        try mutate(id) { $0.status = status }
        for observer in statusObservers[id] ?? [] {
            observer.yield(status)
        }
    }

    @discardableResult
    func compareAndSetStatus(_ id: TransactionId, observed: EntryStatus, verdict: Verdict) async throws -> Bool {
        guard let current = entries[id], current.status.isLive, current.status == observed else { return false }

        let statusChanged = current.status != verdict.status
        guard statusChanged || verdict.successDetectedAt.touchesRecord else { return false }

        try mutate(id) {
            $0.status = verdict.status
            switch verdict.successDetectedAt {
            case .unchanged: break
            case .clear: $0.successDetectedAt = nil
            case let .set(block): $0.successDetectedAt = block
            }
        }
        if statusChanged {
            for observer in statusObservers[id] ?? [] {
                observer.yield(verdict.status)
            }
        }
        return true
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

    nonisolated func subscribeStatus(of id: TransactionId) -> AnyAsyncSequence<EntryStatus> {
        AsyncStream<EntryStatus> { continuation in
            Task { await self.attach(continuation, to: id) }
        }
        .eraseToAnyAsyncSequence()
    }

    func minter(of asset: OwnAsset) async throws -> DurabilityEntry? {
        entries.values.first { $0.outputs.contains(asset) }
    }

    func consumers(of input: DurabilityInput) async throws -> [DurabilityEntry] {
        sortedEntries.filter { $0.inputs.contains(input) }
    }

    /// Test helper: directly records a committed handoff mark (skips the two-phase flow).
    func markHandedOff(_ asset: OwnAsset) async throws {
        committedMarks.insert(asset.identifier)
    }

    func markHandoffPending(_ assets: [OwnAsset]) async throws {
        for asset in assets where !committedMarks.contains(asset.identifier) {
            pendingMarks.insert(asset.identifier)
        }
    }

    func commitHandoffs(_ assets: [OwnAsset]) async throws {
        for asset in assets {
            pendingMarks.remove(asset.identifier)
            committedMarks.insert(asset.identifier)
        }
    }

    func releaseUncommittedHandoffs() async throws {
        pendingMarks.removeAll()
    }

    func hasEverBeenHandedOff(_ asset: OwnAsset) async throws -> Bool {
        handoffIdentifiers.contains(asset.identifier)
    }

    func handedOffCoins() async throws -> [OwnAsset] {
        handoffIdentifiers.compactMap { identifier in
            let parts = identifier.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let index = UInt64(parts[1]) else { return nil }

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

    func attach(_ continuation: AsyncStream<EntryStatus>.Continuation, to id: TransactionId) {
        if let entry = entries[id] {
            continuation.yield(entry.status)
        }
        statusObservers[id, default: []].append(continuation)
    }

    func mutate(_ id: TransactionId, _ change: (inout DurabilityEntry) -> Void) throws {
        guard var entry = entries[id] else {
            throw DurabilityError.entryNotFound(id)
        }
        change(&entry)
        entries[id] = entry
    }
}
