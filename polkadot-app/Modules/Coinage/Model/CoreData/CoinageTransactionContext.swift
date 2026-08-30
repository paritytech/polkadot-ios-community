import Coinage
import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency
import SubstrateSdk

/// Manages transactional read-validate-write operations on the shared CoreData store.
/// All writes via `withTransaction` use the shared context from `CoreDataService`, ensuring
/// atomicity and consistency with `subscribeSnapshot` readers.
///
/// WARNING: Do not call `withTransaction` from within another `withTransaction` body.
/// This would deadlock on the shared serial dispatch queue. Verified callers in
/// `DurabilityCoreDataStore` (register, handoff marks) are never nested.
final class CoinageTransactionContext: CoinageTransacting, @unchecked Sendable {
    private let databaseService: CoreDataServiceProtocol

    init(databaseService: CoreDataServiceProtocol) {
        self.databaseService = databaseService
    }

    /// Executes a transaction block within the shared CoreData context.
    /// Saves all changes if `body` completes successfully, or rolls back on error.
    ///
    /// Invariant: `context.save()` commits whatever is pending on the shared context.
    /// This holds today because every `CoreDataRepository` write saves-or-rolls-back within
    /// its own `perform` block, but this is a convention and is unenforced app-wide.
    /// A future writer that mutates the shared context and defers its save would be committed by this `save()`.
    func withTransaction<T>(_ body: @escaping (CoinageStoreTransaction) throws -> T) async throws -> T {
        try await databaseService.perform { context in
            do {
                let transaction = Transaction(context: context)
                let result = try body(transaction)
                try context.save()
                return result
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}

// MARK: - Transaction

private class Transaction: CoinageStoreTransaction {
    private let context: NSManagedObjectContext
    private let entryMapper = DurabilityEntryMapper()

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func filterMinted(_ keys: Set<PublicKey>) throws -> Set<PublicKey> {
        guard !keys.isEmpty else { return [] }
        let hexKeys = keys.map { $0.toHex() }
        let request = NSFetchRequest<CDDurabilityOutput>(entityName: "CDDurabilityOutput")
        request.predicate = NSPredicate(format: "coin.publicKey IN %@ OR voucher.publicKey IN %@", hexKeys, hexKeys)
        return try matched(context.fetch(request).map { [$0.coin?.publicKey, $0.voucher?.publicKey] }, in: keys)
    }

    func filterReceived(_ keys: Set<PublicKey>) throws -> Set<PublicKey> {
        guard !keys.isEmpty else { return [] }
        let request = NSFetchRequest<CDDurabilityInput>(entityName: "CDDurabilityInput")
        request.predicate = NSPredicate(
            format: "%K IN %@", #keyPath(CDDurabilityInput.receivedPubKey), keys.map { $0.toHex() }
        )
        return try matched(context.fetch(request).map { [$0.receivedPubKey] }, in: keys)
    }

    func filterClaimed(_ keys: Set<PublicKey>) throws -> Set<PublicKey> {
        guard !keys.isEmpty else { return [] }
        let hexKeys = keys.map { $0.toHex() }
        let assetMatch = NSPredicate(
            format: "coin.publicKey IN %@ OR voucher.publicKey IN %@ OR %K IN %@",
            hexKeys, hexKeys, #keyPath(CDDurabilityInput.receivedPubKey), hexKeys
        )
        let nonFailure = NSPredicate(
            format: "%K.%K != %d",
            #keyPath(CDDurabilityInput.entry), #keyPath(CDDurability.status), EntryStatus.failure.rawValue
        )
        let request = NSFetchRequest<CDDurabilityInput>(entityName: "CDDurabilityInput")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [assetMatch, nonFailure])
        return try matched(
            context.fetch(request).map { [$0.coin?.publicKey, $0.voucher?.publicKey, $0.receivedPubKey] },
            in: keys
        )
    }

    func filterHandedOff(_ keys: Set<PublicKey>) throws -> Set<PublicKey> {
        guard !keys.isEmpty else { return [] }
        let request = NSFetchRequest<CDCoin>(entityName: "CDCoin")
        request.predicate = NSPredicate(
            format: "publicKey IN %@ AND handoffMark != %d",
            keys.map { $0.toHex() }, Int(CoinHandoffMark.none.rawValue)
        )
        return try matched(context.fetch(request).map { [$0.publicKey] }, in: keys)
    }

    func nextSequence() throws -> Int64 {
        let request = NSFetchRequest<CDDurability>(entityName: "CDDurability")
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(CDDurability.sequence), ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false

        let entities = try context.fetch(request)
        return (entities.first?.sequence ?? 0) + 1
    }

    func upsert(_ entry: DurabilityEntry) throws {
        let request = NSFetchRequest<CDDurability>(entityName: Self.entryEntity)
        request.predicate = NSPredicate(
            format: "%K = %@",
            #keyPath(CDDurability.identifier),
            entry.identifier
        )

        guard let entity = try context.fetch(request).first ?? insert(Self.entryEntity) else {
            throw DurabilityError.entryNotFound(entry.id)
        }

        try entryMapper.populate(entity: entity, from: entry, using: context)
    }

    func entry(_ id: TransactionId) throws -> DurabilityEntry? {
        let request = NSFetchRequest<CDDurability>(entityName: Self.entryEntity)
        request.predicate = NSPredicate(format: "%K = %@", #keyPath(CDDurability.identifier), id.uuidString)
        request.fetchLimit = 1
        guard let entity = try context.fetch(request).first else { return nil }
        return try entryMapper.transform(entity: entity)
    }

    func markHandoffPending(_ asset: OwnAsset) throws {
        guard let coin = try coinRow(for: asset) else { return }
        // Never regress a committed mark back to provisional.
        if coin.handoffMark == CoinHandoffMark.none.rawValue {
            coin.handoffMark = CoinHandoffMark.pending.rawValue
        }
    }

    func commitHandoff(_ asset: OwnAsset) throws {
        try coinRow(for: asset)?.handoffMark = CoinHandoffMark.committed.rawValue
    }

    func releaseUncommittedMarks() throws {
        let request = NSFetchRequest<CDCoin>(entityName: "CDCoin")
        request.predicate = NSPredicate(
            format: "handoffMark == %d", Int(CoinHandoffMark.pending.rawValue)
        )
        for coin in try context.fetch(request) {
            coin.handoffMark = CoinHandoffMark.none.rawValue
        }
    }

    private func coinRow(for asset: OwnAsset) throws -> CDCoin? {
        guard case let .coin(index) = asset else { return nil }

        let request = NSFetchRequest<CDCoin>(entityName: "CDCoin")
        request.predicate = NSPredicate(format: "identifier == %@", Coin.identifier(for: index))
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

private extension Transaction {
    static var entryEntity: String { "CDDurability" }

    func insert<Entity: NSManagedObject>(_ entityName: String) -> Entity? {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as? Entity
    }

    /// The subset of `keys` present among the fetched rows' public-key hex strings (a row may carry
    /// several — a coin, a voucher, or a received key), so a matched row reports back the exact key.
    func matched(_ rowKeyHexes: [[String?]], in keys: Set<PublicKey>) throws -> Set<PublicKey> {
        var result: Set<PublicKey> = []
        for hexes in rowKeyHexes {
            for hex in hexes.compactMap({ $0 }) {
                let data = try Data(hexString: hex)
                if keys.contains(data) { result.insert(data) }
            }
        }
        return result
    }
}
