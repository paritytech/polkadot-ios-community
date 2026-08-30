import Foundation

/// The public-key-keyed reads a registration validates against, all inside one store transaction —
/// nothing it checks can move before the entry is written. Mirrors Android's
/// `RegistrationValidationScope`.
///
/// Every asset is identified by its on-chain public key: an own coin or voucher by the key derived
/// from its index, a coin received from a peer by the key itself. One key space covers them all,
/// which is why the four checks take and return `Set<PublicKey>`.
public protocol CoinageTxValidationContext {
    /// Of `keys`, those already minted as an output by any entry.
    func filterMinted(_ keys: Set<PublicKey>) throws -> Set<PublicKey>
    /// Of `keys`, those recorded as a received-coin input by any entry.
    func filterReceived(_ keys: Set<PublicKey>) throws -> Set<PublicKey>
    /// Of `keys`, those already claimed as an input by a non-failure entry.
    func filterClaimed(_ keys: Set<PublicKey>) throws -> Set<PublicKey>
    /// Of `keys`, those carrying a handoff mark.
    func filterHandedOff(_ keys: Set<PublicKey>) throws -> Set<PublicKey>
}

/// One atomic unit of durability persistence.
///
/// Every method runs inside a single store transaction; nothing is visible until the
/// transaction commits. Registration validates through ``CoinageTxValidationContext`` and then
/// writes, so a rejected registration leaves nothing behind.
public protocol CoinageStoreTransaction: CoinageTxValidationContext {
    /// Next sequence number to assign to a new entry.
    func nextSequence() throws -> Int64
    func upsert(_ entry: DurabilityEntry) throws

    /// The entry with this id as it stands inside the transaction — the read half of a
    /// compare-and-set, so the status it returns cannot move before the write.
    func entry(_ id: TransactionId) throws -> DurabilityEntry?

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
