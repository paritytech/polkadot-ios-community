import Foundation

/// One atomic unit of durability persistence.
///
/// Every method runs inside a single store transaction; nothing is visible until the
/// transaction commits. Registration validates using predicated lookups and then
/// writes, so a rejected registration leaves nothing behind.
public protocol CoinageStoreTransaction {
    /// The subset of `inputs` already claimed as an input by a non-failure entry.
    func claimedInputs(among inputs: Set<DurabilityInput>) throws -> Set<DurabilityInput>
    /// The subset of `outputs` already minted as an output by any entry.
    func mintedOutput(among outputs: Set<DurabilityOutput>) throws -> Set<DurabilityOutput>
    /// The subset of `publicKeys` already claimed as a received-coin input by any entry.
    func receivedInputPublicKeys(among publicKeys: Set<Data>) throws -> Set<Data>
    /// The subset of `inputs` carrying a handoff mark.
    func handedOff(among inputs: Set<DurabilityInput>) throws -> Set<DurabilityInput>
    /// Next sequence number to assign to a new entry.
    func nextSequence() throws -> Int64
    func upsert(_ entry: DurabilityEntry) throws
    func insertMark(_ asset: OwnAsset) throws

    /// Provisionally marks an asset handed off (`.pending`), before its keys reach the transport.
    /// A no-op if the asset already carries a committed mark, so commit never regresses.
    func markHandoffPending(_ asset: OwnAsset) throws
    /// Promotes an asset's provisional mark to final (`.committed`).
    func commitHandoff(_ asset: OwnAsset) throws
    /// Clears every provisional (`.pending`) mark — payments whose keys never durably left.
    func releaseUncommittedMarks() throws
}

/// Runs a body inside one store transaction.
public protocol CoinageTransacting: Sendable {
    func withTransaction<T>(_ body: @escaping (CoinageStoreTransaction) throws -> T) async throws -> T
}
