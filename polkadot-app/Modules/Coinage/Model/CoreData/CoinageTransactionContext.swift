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

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func claimedInputs(among inputs: Set<DurabilityInput>) throws -> Set<DurabilityInput> {
        let rows = try matchingInputRows(for: Array(inputs), nonFailureOnly: true)
        return Set(rows.compactMap(durabilityInput(from:)))
    }

    func mintedOutput(among outputs: Set<DurabilityOutput>) throws -> Set<DurabilityOutput> {
        let rows = try matchingOutputRows(for: Array(outputs))
        return Set(rows.compactMap(durabilityOutput(from:)))
    }

    func receivedInputPublicKeys(among publicKeys: Set<Data>) throws -> Set<Data> {
        guard !publicKeys.isEmpty else { return [] }

        let request = NSFetchRequest<CDDurabilityInput>(entityName: "CDDurabilityInput")
        request.predicate = NSPredicate(
            format: "%K IN %@", #keyPath(CDDurabilityInput.receivedPubKey), publicKeys.map { $0.toHex() }
        )

        let matched = try context.fetch(request).compactMap(\.receivedPubKey)
        return Set(matched.compactMap { try? Data(hexString: $0) })
    }

    func handedOff(among inputs: Set<DurabilityInput>) throws -> Set<DurabilityInput> {
        var inputsByIndex: [Int64: DurabilityInput] = [:]
        for input in inputs {
            if case let .coin(.own(index)) = input { inputsByIndex[index.toCoreData()] = input }
        }
        guard !inputsByIndex.isEmpty else { return [] }

        let request = NSFetchRequest<CDCoin>(entityName: "CDCoin")
        request.predicate = NSPredicate(
            format: "derivationIndex IN %@ AND handoffMark != %d",
            Array(inputsByIndex.keys).map { NSNumber(value: $0) },
            Int(CoinHandoffMark.none.rawValue)
        )

        return try Set(context.fetch(request).compactMap { inputsByIndex[$0.derivationIndex] })
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
        // Insert-only: the mark goes down before the keys leave and is never retracted.
        try coinRow(for: asset)?.handoffMark = CoinHandoffMark.committed.rawValue
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

    func matchingInputRows(for inputs: [DurabilityInput], nonFailureOnly: Bool) throws -> [CDDurabilityInput] {
        let coinIndices = inputs.compactMap { input -> Int64? in
            if case let .coin(.own(index)) = input { return index.toCoreData() }
            return nil
        }
        let voucherIndices = inputs.compactMap { input -> Int64? in
            if case let .recyclerVoucher(index) = input { return index.toCoreData() }
            return nil
        }
        let receivedKeys = inputs.compactMap { input -> String? in
            if case let .coin(.received(data)) = input { return data.toHex() }
            return nil
        }

        var subpredicates: [NSPredicate] = []
        if !coinIndices.isEmpty {
            subpredicates.append(NSPredicate(
                format: "coin.derivationIndex IN %@",
                coinIndices.map { NSNumber(value: $0) }
            ))
        }
        if !voucherIndices.isEmpty {
            subpredicates.append(NSPredicate(
                format: "voucher.derivationIndex IN %@",
                voucherIndices.map { NSNumber(value: $0) }
            ))
        }
        if !receivedKeys.isEmpty {
            subpredicates.append(NSPredicate(
                format: "%K IN %@",
                #keyPath(CDDurabilityInput.receivedPubKey),
                receivedKeys
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

    func matchingOutputRows(for outputs: [DurabilityOutput]) throws -> [CDDurabilityOutput] {
        let coinIndices = outputs.compactMap { asset -> Int64? in
            if case let .coin(index) = asset { return index.toCoreData() }
            return nil
        }
        let voucherIndices = outputs.compactMap { asset -> Int64? in
            if case let .recyclerVoucher(index) = asset { return index.toCoreData() }
            return nil
        }

        var subpredicates: [NSPredicate] = []
        if !coinIndices.isEmpty {
            subpredicates.append(NSPredicate(
                format: "coin.derivationIndex IN %@",
                coinIndices.map { NSNumber(value: $0) }
            ))
        }
        if !voucherIndices.isEmpty {
            subpredicates.append(NSPredicate(
                format: "voucher.derivationIndex IN %@",
                voucherIndices.map { NSNumber(value: $0) }
            ))
        }
        guard !subpredicates.isEmpty else { return [] }

        let request = NSFetchRequest<CDDurabilityOutput>(entityName: "CDDurabilityOutput")
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
        return try context.fetch(request)
    }

    /// Reconstructs the typed input an input row references, from its relations / received key.
    func durabilityInput(from row: CDDurabilityInput) -> DurabilityInput? {
        if let hex = row.receivedPubKey, let publicKey = try? Data(hexString: hex) {
            return .coin(.received(publicKey))
        }
        if let coin = row.coin {
            return .coin(.own(DerivationIndex.fromCoreData(coin.derivationIndex)))
        }
        if let voucher = row.voucher {
            return .recyclerVoucher(DerivationIndex.fromCoreData(voucher.derivationIndex))
        }
        return nil
    }

    /// Reconstructs the typed output an output row references, from its relations.
    func durabilityOutput(from row: CDDurabilityOutput) -> DurabilityOutput? {
        if let coin = row.coin {
            return .coin(DerivationIndex.fromCoreData(coin.derivationIndex))
        }
        if let voucher = row.voucher {
            return .recyclerVoucher(DerivationIndex.fromCoreData(voucher.derivationIndex))
        }
        return nil
    }
}
