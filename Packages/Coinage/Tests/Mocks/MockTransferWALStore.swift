import Foundation
@testable import Coinage

/// Recording `TransferWALStoring` mock shared by the recovery and recycling test suites.
///
/// - `fetchAllResult` seeds what `fetchAll()` returns (recovery startup simulation).
/// - `deletedIds` records every `delete(id:)`.
/// - `entries` is the live set (saved minus deleted), for asserting the WAL was cleared.
actor MockTransferWALStore: TransferWALStoring {
    private(set) var savedEntries: [TransferWALEntry] = []
    private(set) var deletedIds: [UUID] = []
    private var liveEntries: [UUID: TransferWALEntry] = [:]
    nonisolated(unsafe) var fetchAllResult: [TransferWALEntry] = []

    var entries: [TransferWALEntry] { Array(liveEntries.values) }

    func save(_ entry: TransferWALEntry) async throws {
        savedEntries.append(entry)
        liveEntries[entry.id] = entry
    }

    func update(id _: UUID, checkpointBlock _: CheckpointBlock) async throws {
        // Not tested in recovery scenarios
    }

    func fetchAll() async throws -> [TransferWALEntry] {
        fetchAllResult
    }

    func save(contentsOf entries: [TransferWALEntry]) async throws {
        savedEntries.append(contentsOf: entries)
        for entry in entries {
            liveEntries[entry.id] = entry
        }
    }

    func delete(id: UUID) async throws {
        deletedIds.append(id)
        liveEntries[id] = nil
    }
}
