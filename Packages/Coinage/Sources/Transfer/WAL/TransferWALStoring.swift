import Foundation

/// Persistence layer for transfer WAL entries.
public protocol TransferWALStoring: Sendable {
    /// Saves a new WAL entry.
    func save(_ entry: TransferWALEntry) async throws

    /// Updates extrinsic hash and checkpoint block (number + hash) in tandem.
    func update(id: UUID, checkpointBlock: CheckpointBlock) async throws

    /// Fetches all WAL entries (typically on app startup).
    func fetchAll() async throws -> [TransferWALEntry]

    /// Saves multiple WAL entries (used for batch group write before task group launch).
    func save(contentsOf entries: [TransferWALEntry]) async throws

    /// Deletes a WAL entry by ID.
    func delete(id: UUID) async throws
}
