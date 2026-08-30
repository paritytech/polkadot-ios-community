import AsyncExtensions
import Foundation
@testable import Coinage

actor MockCoinageTxRepository: CoinageTxRepositoryProtocol {
    private var entries: [CoinageTxId: CoinageTxEntry] = [:]
    private var pendingMarks: Set<String> = []
    private var committedMarks: Set<String> = []
    private var nextSequence: Int64 = 1
    private var statusObservers: [CoinageTxId: [AsyncStream<CoinageTxStatus>.Continuation]] = [:]

    var allEntries: [CoinageTxEntry] {
        sortedEntries
    }

    var handoffIdentifiers: Set<String> {
        pendingMarks.union(committedMarks)
    }

    /// Convenience for the many tests that register without an extra validation closure — the
    /// mock enforces the invariants inline (by identifier), independent of the closure the real
    /// store runs.
    func register(_ entry: CoinageTxEntry) async throws {
        try await register(entry) { _ in }
    }

    /// Atomic batch: on any failure the whole batch is rolled back, matching the store's single
    /// transaction. The inline `register` already dedups a later entry against earlier ones,
    /// since each is inserted before the next is validated.
    func registerAll(
        _ entries: [CoinageTxEntry],
        validation _: @escaping (CoinageTxEntry, any CoinageTxValidationContext) throws -> Void
    ) async throws {
        let entriesSnapshot = self.entries
        let sequenceSnapshot = nextSequence
        do {
            for entry in entries {
                try await register(entry)
            }
        } catch {
            self.entries = entriesSnapshot
            nextSequence = sequenceSnapshot
            throw error
        }
    }

    func register(
        _ entry: CoinageTxEntry,
        validation _: @escaping (any CoinageTxValidationContext) throws -> Void
    ) async throws {
        guard !entry.inputs.isEmpty || !entry.outputs.isEmpty else {
            throw CoinageTxError.emptyEntry
        }

        let mintedOutputs = Set(entries.values.flatMap { $0.outputs.map(\.identifier) })
        if let duplicate = entry.outputs.first(where: { mintedOutputs.contains($0.identifier) }) {
            throw CoinageTxError.outputNotFresh(duplicate.identifier)
        }

        let claimedInputs = Set(
            entries.values
                .filter { $0.status != .failure }
                .flatMap { $0.inputs.map(\.identifier) }
        )
        if let claimed = entry.inputs.first(where: { claimedInputs.contains($0.identifier) }) {
            throw CoinageTxError.inputAlreadyClaimed(claimed.identifier)
        }

        let marks = handoffIdentifiers
        if let marked = entry.inputs.first(where: { marks.contains($0.identifier) }) {
            throw CoinageTxError.inputHandedOff(marked.identifier)
        }

        var sequenced = entry
        sequenced.sequence = nextSequence
        entries[entry.id] = sequenced
        nextSequence += 1
    }

    func updateStatus(_ id: CoinageTxId, to status: CoinageTxStatus) async throws {
        try mutate(id) { $0.status = status }
        for observer in statusObservers[id] ?? [] {
            observer.yield(status)
        }
    }

    @discardableResult
    func compareAndSetStatus(_ id: CoinageTxId, observed: CoinageTxStatus, verdict: Verdict) async throws -> Bool {
        guard let current = entries[id], current.status.isLive, current.status == observed else { return false }

        let statusChanged = current.status != verdict.status
        guard statusChanged || current.successDetectedAt != verdict.successDetectedAt else { return false }

        try mutate(id) {
            $0.status = verdict.status
            $0.successDetectedAt = verdict.successDetectedAt
        }
        if statusChanged {
            for observer in statusObservers[id] ?? [] {
                observer.yield(verdict.status)
            }
        }
        return true
    }

    func recordSuccessDetected(_ id: CoinageTxId, at block: BlockRef?) async throws {
        try mutate(id) { $0.successDetectedAt = block }
    }

    func recordTxHash(_ id: CoinageTxId, txHash: Data) async throws {
        try mutate(id) { $0.txHash = txHash }
    }

    func fetchLive() async throws -> [CoinageTxEntry] {
        sortedEntries.filter(\.status.isLive)
    }

    func fetchAll() async throws -> [CoinageTxEntry] {
        sortedEntries
    }

    func fetch(id: CoinageTxId) async throws -> CoinageTxEntry? {
        entries[id]
    }

    nonisolated func subscribeStatus(of id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus> {
        AsyncStream<CoinageTxStatus> { continuation in
            Task { await self.attach(continuation, to: id) }
        }
        .eraseToAnyAsyncSequence()
    }

    func minter(of asset: OwnAsset) async throws -> CoinageTxEntry? {
        entries.values.first { $0.outputs.contains(asset) }
    }

    func consumers(of input: CoinageTxInput) async throws -> [CoinageTxEntry] {
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

private extension MockCoinageTxRepository {
    var sortedEntries: [CoinageTxEntry] {
        entries.values.sorted { $0.sequence < $1.sequence }
    }

    func attach(_ continuation: AsyncStream<CoinageTxStatus>.Continuation, to id: CoinageTxId) {
        if let entry = entries[id] {
            continuation.yield(entry.status)
        }
        statusObservers[id, default: []].append(continuation)
    }

    func mutate(_ id: CoinageTxId, _ change: (inout CoinageTxEntry) -> Void) throws {
        guard var entry = entries[id] else {
            throw CoinageTxError.entryNotFound(id)
        }
        change(&entry)
        entries[id] = entry
    }
}
