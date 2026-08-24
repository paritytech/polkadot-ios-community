import Coinage
import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

/// Manages transactional read-validate-write operations on the shared CoreData store.
/// All writes via `withTransaction` use the shared context from `CoreDataService`, ensuring
/// atomicity and consistency with `subscribeSnapshot` readers.
///
/// WARNING: Do not call `withTransaction` from within another `withTransaction` body.
/// This would deadlock on the shared serial dispatch queue. Verified callers:
/// `DurabilityCoreDataStore:46` (register) and `:167` (markHandedOff), neither nested.
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
    private let markMapper = HandoffMarkMapper()

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func claimedInputIdentifiers(among candidates: Set<String>) throws -> Set<String> {
        let request = NSFetchRequest<CDEntryAsset>(entityName: "CDEntryAsset")
        request.predicate = NSPredicate(
            format: "%K IN %@ AND %K == 0 AND %K.%K != %d",
            #keyPath(CDEntryAsset.identifier),
            Array(candidates),
            #keyPath(CDEntryAsset.role),
            #keyPath(CDEntryAsset.entry),
            #keyPath(CDDurabilityEntry.status),
            EntryStatus.failure.rawValue
        )

        let results = try context.fetch(request)
        return Set(results.compactMap(\.identifier))
    }

    func mintedOutputIdentifiers(among candidates: Set<String>) throws -> Set<String> {
        let request = NSFetchRequest<CDEntryAsset>(entityName: "CDEntryAsset")
        request.predicate = NSPredicate(
            format: "%K IN %@ AND %K == 1",
            #keyPath(CDEntryAsset.identifier),
            Array(candidates),
            #keyPath(CDEntryAsset.role)
        )

        let results = try context.fetch(request)
        return Set(results.compactMap(\.identifier))
    }

    func receivedInputIdentifiers(among candidates: Set<String>) throws -> Set<String> {
        let request = NSFetchRequest<CDEntryAsset>(entityName: "CDEntryAsset")
        request.predicate = NSPredicate(
            format: "%K IN %@ AND %K == 0 AND %K BEGINSWITH %@",
            #keyPath(CDEntryAsset.identifier),
            Array(candidates),
            #keyPath(CDEntryAsset.role),
            #keyPath(CDEntryAsset.identifier),
            "received:"
        )

        let results = try context.fetch(request)
        return Set(results.compactMap(\.identifier))
    }

    func markedIdentifiers(among candidates: Set<String>) throws -> Set<String> {
        let request = NSFetchRequest<CDHandoffMark>(entityName: "CDHandoffMark")
        request.predicate = NSPredicate(
            format: "%K IN %@",
            #keyPath(CDHandoffMark.identifier),
            Array(candidates)
        )

        let results = try context.fetch(request)
        return Set(results.compactMap(\.identifier))
    }

    func nextSequence() throws -> Int64 {
        let request = NSFetchRequest<CDDurabilityEntry>(entityName: "CDDurabilityEntry")
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(CDDurabilityEntry.sequence), ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false

        let entities = try context.fetch(request)
        return (entities.first?.sequence ?? 0) + 1
    }

    func upsert(_ entry: DurabilityEntry) throws {
        let request = NSFetchRequest<CDDurabilityEntry>(entityName: Self.entryEntity)
        request.predicate = NSPredicate(
            format: "%K = %@",
            #keyPath(CDDurabilityEntry.identifier),
            entry.identifier
        )

        guard let entity = try context.fetch(request).first ?? insert(Self.entryEntity) else {
            throw DurabilityError.entryNotFound(entry.id)
        }

        try entryMapper.populate(entity: entity, from: entry, using: context)
    }

    func insertMark(_ asset: OwnAsset) throws {
        let request = NSFetchRequest<CDHandoffMark>(entityName: Self.markEntity)
        request.predicate = NSPredicate(
            format: "%K = %@",
            #keyPath(CDHandoffMark.identifier),
            asset.identifier
        )

        guard try context.fetch(request).isEmpty else { return }

        guard let entity: CDHandoffMark = insert(Self.markEntity) else {
            throw DurabilityError.entryNotFound(TransactionId())
        }

        let mark = HandoffMark(identifier: asset.identifier, createdAt: Date())
        try markMapper.populate(entity: entity, from: mark, using: context)
    }
}

private extension Transaction {
    static var entryEntity: String { "CDDurabilityEntry" }
    static var markEntity: String { "CDHandoffMark" }

    func insert<Entity: NSManagedObject>(_ entityName: String) -> Entity? {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as? Entity
    }
}
