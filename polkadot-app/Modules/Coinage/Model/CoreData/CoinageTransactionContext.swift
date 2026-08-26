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

    func claimedInputIdentifiers(among inputs: [Input]) throws -> Set<String> {
        let rows = try matchingInputRows(for: inputs, nonFailureOnly: true)
        return Set(rows.compactMap { DurabilityRowCoding.input(from: $0)?.identifier })
    }

    func mintedOutputIdentifiers(among outputs: [OwnAsset]) throws -> Set<String> {
        let rows = try matchingOutputRows(for: outputs)
        return Set(rows.compactMap { DurabilityRowCoding.ownAsset(from: $0)?.identifier })
    }

    func receivedInputIdentifiers(among outputs: [OwnAsset]) throws -> Set<String> {
        let candidates = Set(outputs.map(\.identifier))
        let request = NSFetchRequest<CDDurabilityInput>(entityName: "CDDurabilityInput")
        request.predicate = NSPredicate(format: "%K != nil", #keyPath(CDDurabilityInput.receivedPubKey))

        let identifiers = try context.fetch(request).compactMap { DurabilityRowCoding.input(from: $0)?.identifier }
        return Set(identifiers.filter(candidates.contains))
    }

    func markedIdentifiers(among inputs: [Input]) throws -> Set<String> {
        let identifiers = inputs.compactMap { $0.ownAsset?.identifier }
        guard !identifiers.isEmpty else { return [] }

        let request = NSFetchRequest<CDHandoffMark>(entityName: "CDHandoffMark")
        request.predicate = NSPredicate(format: "%K IN %@", #keyPath(CDHandoffMark.identifier), identifiers)

        return try Set(context.fetch(request).compactMap(\.identifier))
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
    static var entryEntity: String { "CDDurability" }
    static var markEntity: String { "CDHandoffMark" }

    func insert<Entity: NSManagedObject>(_ entityName: String) -> Entity? {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as? Entity
    }

    func matchingInputRows(for inputs: [Input], nonFailureOnly: Bool) throws -> [CDDurabilityInput] {
        let coinIndices = inputs.compactMap { input -> Int64? in
            if case let .coin(.own(index)) = input { return Int64(index) }
            return nil
        }
        let voucherIndices = inputs.compactMap { input -> Int64? in
            if case let .recyclerVoucher(index) = input { return Int64(index) }
            return nil
        }
        let receivedKeys = inputs.compactMap { input -> String? in
            if case let .coin(.received(data)) = input { return data.toHex() }
            return nil
        }

        var subpredicates = assetPredicates(coinIndices: coinIndices, voucherIndices: voucherIndices)
        if !receivedKeys.isEmpty {
            subpredicates.append(NSPredicate(
                format: "%K IN %@", #keyPath(CDDurabilityInput.receivedPubKey), receivedKeys
            ))
        }
        guard !subpredicates.isEmpty else { return [] }

        var predicate: NSPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
        if nonFailureOnly {
            let live = NSPredicate(
                format: "%K.%K != %d",
                #keyPath(CDDurabilityInput.entry),
                #keyPath(CDDurability.status),
                EntryStatus.failure.rawValue
            )
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, live])
        }

        let request = NSFetchRequest<CDDurabilityInput>(entityName: "CDDurabilityInput")
        request.predicate = predicate
        return try context.fetch(request)
    }

    func matchingOutputRows(for outputs: [OwnAsset]) throws -> [CDDurabilityOutput] {
        let coinIndices = outputs.compactMap { asset -> Int64? in
            if case let .coin(index) = asset { return Int64(index) }
            return nil
        }
        let voucherIndices = outputs.compactMap { asset -> Int64? in
            if case let .recyclerVoucher(index) = asset { return Int64(index) }
            return nil
        }

        let subpredicates = assetPredicates(coinIndices: coinIndices, voucherIndices: voucherIndices)
        guard !subpredicates.isEmpty else { return [] }

        let request = NSFetchRequest<CDDurabilityOutput>(entityName: "CDDurabilityOutput")
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
        return try context.fetch(request)
    }

    /// Predicates over the `assetKind` + `derivationIndex` columns shared by input and output rows.
    func assetPredicates(coinIndices: [Int64], voucherIndices: [Int64]) -> [NSPredicate] {
        var predicates: [NSPredicate] = []
        if !coinIndices.isEmpty {
            predicates.append(NSPredicate(
                format: "assetKind == %d AND derivationIndex IN %@",
                Int(DurabilityRowCoding.AssetKind.coin.rawValue),
                coinIndices.map { NSNumber(value: $0) }
            ))
        }
        if !voucherIndices.isEmpty {
            predicates.append(NSPredicate(
                format: "assetKind == %d AND derivationIndex IN %@",
                Int(DurabilityRowCoding.AssetKind.voucher.rawValue),
                voucherIndices.map { NSNumber(value: $0) }
            ))
        }
        return predicates
    }
}
