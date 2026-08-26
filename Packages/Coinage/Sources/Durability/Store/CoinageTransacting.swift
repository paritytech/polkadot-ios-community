import Foundation

/// One atomic unit of durability persistence.
///
/// Every method runs inside a single store transaction; nothing is visible until the
/// transaction commits. Registration validates using predicated lookups and then
/// writes, so a rejected registration leaves nothing behind.
public protocol CoinageStoreTransaction {
    /// Identifiers among `inputs` already claimed as an input by a non-failure entry.
    func claimedInputIdentifiers(among inputs: [Input]) throws -> Set<String>
    /// Identifiers among `outputs` already minted as an output by any entry.
    func mintedOutputIdentifiers(among outputs: [OwnAsset]) throws -> Set<String>
    /// Identifiers among `outputs` already claimed as a received-coin input by any entry.
    func receivedInputIdentifiers(among outputs: [OwnAsset]) throws -> Set<String>
    /// Identifiers among `inputs` carrying a handoff mark.
    func markedIdentifiers(among inputs: [Input]) throws -> Set<String>
    /// Next sequence number to assign to a new entry.
    func nextSequence() throws -> Int64
    func upsert(_ entry: DurabilityEntry) throws
    func insertMark(_ asset: OwnAsset) throws
}

/// Runs a body inside one store transaction.
public protocol CoinageTransacting: Sendable {
    func withTransaction<T>(_ body: @escaping (CoinageStoreTransaction) throws -> T) async throws -> T
}
