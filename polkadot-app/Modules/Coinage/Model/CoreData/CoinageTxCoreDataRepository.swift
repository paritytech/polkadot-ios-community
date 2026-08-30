import AsyncExtensions
import Coinage
import CoreData
import Foundation
import Operation_iOS

/// CoreData-backed ``CoinageTxRepositoryProtocol`` — the consolidation of the former
/// `DurabilityCoreDataStore` (public API) and `CoinageTransactionContext` (the atomic
/// read-validate-write transaction) into one repository. Mirrors Android's `CoinageEntryRepository`.
///
/// Entries are never deleted: `minter(of:)` and `consumers(of:)` must still see terminal rows,
/// because a coin's provenance is what makes its absence mean anything. Handoff marks live on
/// `CDCoin.handoffMark` (insert-only) for the same reason.
///
/// Registration invariants are enforced in one store transaction, so a rejected registration
/// leaves nothing behind. Validation completes before any mutation, and the shared serial
/// `databaseService` queue serialises concurrent registrations.
final class CoinageTxCoreDataRepository: CoinageTxRepositoryProtocol, @unchecked Sendable {
    private let repository: AnyDataProviderRepository<CoinageTxEntry>
    private let coinRepository: AnyDataProviderRepository<Coin>
    private let storageFacade: StorageFacadeProtocol
    private let databaseService: CoreDataServiceProtocol

    init(storageFacade: StorageFacadeProtocol) {
        self.storageFacade = storageFacade
        databaseService = storageFacade.databaseService

        let entryRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDDurability.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(CoinageTxEntryMapper())
        )
        repository = AnyDataProviderRepository(entryRepository)

        let coins = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(CoinMapper())
        )
        coinRepository = AnyDataProviderRepository(coins)
    }
}

// MARK: - Registration

extension CoinageTxCoreDataRepository {
    func register(
        _ entry: CoinageTxEntry,
        validation: @escaping (any CoinageTxValidationContext) throws -> Void
    ) async throws {
        try await withTransaction { transaction in
            try validation(transaction)

            var sequenced = entry
            sequenced.sequence = try transaction.nextSequence()

            try transaction.upsert(sequenced)
        }
    }

    func registerAll(
        _ entries: [CoinageTxEntry],
        validation: @escaping (CoinageTxEntry, any CoinageTxValidationContext) throws -> Void
    ) async throws {
        guard !entries.isEmpty else { return }
        try await withTransaction { transaction in
            // Validate-then-insert each in turn: `nextSequence` and the validation filters both
            // read the transaction's pending changes, so entry N is checked against every earlier
            // entry in this batch as well as the committed store.
            for entry in entries {
                try validation(entry, transaction)

                var sequenced = entry
                sequenced.sequence = try transaction.nextSequence()

                try transaction.upsert(sequenced)
            }
        }
    }
}

// MARK: - Field and status writes

extension CoinageTxCoreDataRepository {
    func updateStatus(_ id: CoinageTxId, to status: CoinageTxStatus) async throws {
        try await write(id, \.status, status)
    }

    @discardableResult
    func updateTxStatus(
        for id: CoinageTxId,
        expectedCurrentStatus: CoinageTxStatus,
        verdict: Verdict
    ) async throws -> Bool {
        try await withTransaction { transaction in
            guard var entry = try transaction.entry(id) else { return false }
            guard entry.status.isLive, entry.status == expectedCurrentStatus else { return false }

            // Skip a write that changes nothing — a verdict restating the current status and record.
            guard entry.status != verdict.status || entry.successDetectedAt != verdict.successDetectedAt else {
                return false
            }

            entry.status = verdict.status
            entry.successDetectedAt = verdict.successDetectedAt
            try transaction.upsert(entry)
            return true
        }
    }

    func recordSuccessDetected(_ id: CoinageTxId, at block: BlockRef?) async throws {
        try await write(id, \.successDetectedAt, block)
    }

    func recordTxHash(_ id: CoinageTxId, txHash: Data) async throws {
        try await write(id, \.txHash, txHash)
    }

    /// Field and status writes go through the same serialized transaction as registration, so they
    /// share one context with the `subscribeSnapshot` readers and never race a concurrent write.
    /// `upsert` re-populates the existing row; the mapper leaves its immutable inputs/outputs alone.
    private func write<Value>(
        _ id: CoinageTxId,
        _ field: WritableKeyPath<CoinageTxEntry, Value>,
        _ value: Value
    ) async throws {
        guard var entry = try await getEntry(id: id) else {
            throw CoinageTxError.entryNotFound(id)
        }
        entry[keyPath: field] = value
        try await withTransaction { try $0.upsert(entry) }
    }
}

// MARK: - Reads

extension CoinageTxCoreDataRepository {
    func hasLiveEntries() async throws -> Bool {
        try await getAllEntries().contains(where: \.status.isLive)
    }

    func getAllEntries() async throws -> [CoinageTxEntry] {
        try await repository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .sorted { $0.sequence < $1.sequence }
    }

    func getEntry(id: CoinageTxId) async throws -> CoinageTxEntry? {
        try await repository.fetchOperation(
            by: { id.uuidString },
            options: RepositoryFetchOptions()
        ).asyncExecute()
    }

    func subscribeStatus(id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus> {
        storageFacade.subscribeSingle(
            mapper: AnyCoreDataMapper(CoinageTxEntryMapper()),
            filter: NSPredicate(format: "%K == %@", #keyPath(CDDurability.identifier), id.uuidString)
        )
        .compactMap { $0?.status }
        .eraseToAnyAsyncSequence()
    }

    func minter(of asset: OwnAsset) async throws -> CoinageTxEntry? {
        let key = asset.publicKey
        return try await getAllEntries().first { entry in
            entry.outputs.contains { $0.publicKey == key }
        }
    }

    func consumers(of input: CoinageTxInput) async throws -> [CoinageTxEntry] {
        let key = input.publicKey
        return try await getAllEntries().filter { entry in
            entry.inputs.contains { $0.publicKey == key }
        }
    }
}

// MARK: - Handoff marks

extension CoinageTxCoreDataRepository {
    func precommitHandOff(_ assets: [OwnAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await withTransaction { transaction in
            for asset in assets {
                try transaction.markHandoffPending(asset)
            }
        }
    }

    func commitHandoffs(_ keys: [PublicKey]) async throws {
        guard !keys.isEmpty else { return }
        try await withTransaction { transaction in
            for key in keys {
                try transaction.commitHandoff(key: key)
            }
        }
    }

    func releaseUncommittedHandoffs() async throws {
        try await withTransaction { try $0.releaseUncommittedMarks() }
    }

    func hasEverBeenHandedOff(_ asset: OwnAsset) async throws -> Bool {
        guard case let .coin(index, _) = asset else { return false }
        return try await handedOffCoinModels().contains { $0.derivationIndex == index }
    }

    func handedOffCoins() async throws -> [OwnAsset] {
        try await handedOffCoinModels().map { .coin($0.derivationIndex, $0.publicKey) }
    }

    /// The handoff mark is stored on `CDCoin`, so a non-`.none` `handoffMark` identifies a
    /// handed-off coin. The mark is insert-only, so this never mistakes a released coin for one.
    private func handedOffCoinModels() async throws -> [Coin] {
        try await coinRepository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .filter { $0.handoffMark != .none }
    }
}

// MARK: - Transaction

private extension CoinageTxCoreDataRepository {
    /// Executes a transaction block within the shared CoreData context, saving on success and
    /// rolling back on error, so a rejected registration leaves nothing behind.
    ///
    /// WARNING: Do not call `withTransaction` from within another `withTransaction` body — that
    /// would deadlock on the shared serial dispatch queue. The callers above never nest.
    ///
    /// Invariant: `context.save()` commits whatever is pending on the shared context. This holds
    /// today because every `CoreDataRepository` write saves-or-rolls-back within its own `perform`
    /// block, but this is a convention and is unenforced app-wide.
    func withTransaction<T>(_ body: @escaping (Transaction) throws -> T) async throws -> T {
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

/// One atomic unit of durability persistence, scoped to a single `NSManagedObjectContext`.
///
/// It exposes the public-key-keyed reads a registration validates against
/// (``CoinageTxValidationContext``) plus the internal sequence/upsert/handoff writes; nothing is
/// visible until the enclosing `withTransaction` commits.
private final class Transaction: CoinageTxValidationContext {
    private let context: NSManagedObjectContext
    private let entryMapper = CoinageTxEntryMapper()

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
            #keyPath(CDDurabilityInput.entry), #keyPath(CDDurability.status), CoinageTxStatus.failure.rawValue
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

    func upsert(_ entry: CoinageTxEntry) throws {
        let request = NSFetchRequest<CDDurability>(entityName: Self.entryEntity)
        request.predicate = NSPredicate(
            format: "%K = %@",
            #keyPath(CDDurability.identifier),
            entry.identifier
        )

        guard let entity = try context.fetch(request).first ?? insert(Self.entryEntity) else {
            throw CoinageTxError.entryNotFound(entry.id)
        }

        try entryMapper.populate(entity: entity, from: entry, using: context)
    }

    func entry(_ id: CoinageTxId) throws -> CoinageTxEntry? {
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

    func commitHandoff(key: PublicKey) throws {
        let request = NSFetchRequest<CDCoin>(entityName: "CDCoin")
        request.predicate = NSPredicate(format: "publicKey == %@", key.toHex())
        request.fetchLimit = 1
        try context.fetch(request).first?.handoffMark = CoinHandoffMark.committed.rawValue
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
        guard case let .coin(index, _) = asset else { return nil }

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
