import AsyncExtensions
import Coinage
import CoreData
import Foundation
import Operation_iOS

/// CoreData-backed ``DurabilityStoring``.
///
/// Entries are never deleted: `minter(of:)` and `consumers(of:)` must still see terminal rows,
/// because a coin's provenance is what makes its absence mean anything. Handoff marks live in
/// their own insert-only table for the same reason.
///
/// Registration invariants are enforced in one store transaction, so a rejected registration
/// leaves nothing behind. Validation completes before any mutation, and the transaction's
/// private queue serialises concurrent registrations.
final class DurabilityCoreDataStore: DurabilityStoring, @unchecked Sendable {
    private let repository: AnyDataProviderRepository<DurabilityEntry>
    private let coinRepository: AnyDataProviderRepository<Coin>
    private let transacting: any CoinageTransacting
    private let validator: RegistrationValidator
    private let storageFacade: StorageFacadeProtocol

    init(
        storageFacade: StorageFacadeProtocol,
        transacting: any CoinageTransacting,
        coinKeyDeriver: any CoinKeyDeriving
    ) {
        self.storageFacade = storageFacade
        let entryRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDDurability.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(DurabilityEntryMapper())
        )
        repository = AnyDataProviderRepository(entryRepository)

        let coins = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(CoinMapper())
        )
        coinRepository = AnyDataProviderRepository(coins)
        self.transacting = transacting
        validator = RegistrationValidator(coinKeyDeriver: coinKeyDeriver)
    }
}

// MARK: - Registration

extension DurabilityCoreDataStore {
    func register(_ entry: DurabilityEntry) async throws {
        try await transacting.withTransaction { [validator] transaction in
            try validator.validate(entry, transaction: transaction)

            var sequenced = entry
            sequenced.sequence = try transaction.nextSequence()

            try transaction.upsert(sequenced)
        }
    }
}

// MARK: - Field and status writes

extension DurabilityCoreDataStore {
    func updateStatus(_ id: TransactionId, to status: EntryStatus) async throws {
        try await write(id, \.status, status)
    }

    func recordSuccessDetected(_ id: TransactionId, at block: BlockRef?) async throws {
        try await write(id, \.successDetectedAt, block)
    }

    func recordTxHash(_ id: TransactionId, txHash: Data) async throws {
        try await write(id, \.txHash, txHash)
    }

    /// Field and status writes go through the same serialized transaction as registration, so they
    /// share one context with the `subscribeSnapshot` readers and never race a concurrent write.
    /// `upsert` re-populates the existing row; the mapper leaves its immutable inputs/outputs alone.
    private func write<Value>(
        _ id: TransactionId,
        _ field: WritableKeyPath<DurabilityEntry, Value>,
        _ value: Value
    ) async throws {
        guard var entry = try await fetch(id: id) else {
            throw DurabilityError.entryNotFound(id)
        }
        entry[keyPath: field] = value
        try await transacting.withTransaction { try $0.upsert(entry) }
    }
}

// MARK: - Reads

extension DurabilityCoreDataStore {
    func fetchLive() async throws -> [DurabilityEntry] {
        try await fetchAll().filter(\.status.isLive)
    }

    func fetchAll() async throws -> [DurabilityEntry] {
        try await repository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .sorted { $0.sequence < $1.sequence }
    }

    func fetch(id: TransactionId) async throws -> DurabilityEntry? {
        try await repository.fetchOperation(
            by: { id.uuidString },
            options: RepositoryFetchOptions()
        ).asyncExecute()
    }

    func subscribeStatus(of id: TransactionId) -> AnyAsyncSequence<EntryStatus> {
        storageFacade.subscribeSingle(
            mapper: AnyCoreDataMapper(DurabilityEntryMapper()),
            filter: NSPredicate(format: "%K == %@", #keyPath(CDDurability.identifier), id.uuidString)
        )
        .compactMap { $0?.status }
        .eraseToAnyAsyncSequence()
    }

    func minter(of asset: OwnAsset) async throws -> DurabilityEntry? {
        let identifier = asset.identifier
        return try await fetchAll().first { entry in
            entry.outputs.contains { $0.identifier == identifier }
        }
    }

    func consumers(of input: DurabilityInput) async throws -> [DurabilityEntry] {
        let identifier = input.identifier
        return try await fetchAll().filter { entry in
            entry.inputs.contains { $0.identifier == identifier }
        }
    }
}

// MARK: - Handoff marks

extension DurabilityCoreDataStore {
    func markHandoffPending(_ assets: [OwnAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await transacting.withTransaction { transaction in
            for asset in assets {
                try transaction.markHandoffPending(asset)
            }
        }
    }

    func commitHandoffs(_ assets: [OwnAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await transacting.withTransaction { transaction in
            for asset in assets {
                try transaction.commitHandoff(asset)
            }
        }
    }

    func releaseUncommittedHandoffs() async throws {
        try await transacting.withTransaction { try $0.releaseUncommittedMarks() }
    }

    func hasEverBeenHandedOff(_ asset: OwnAsset) async throws -> Bool {
        guard case let .coin(index) = asset else { return false }
        return try await handedOffCoinModels().contains { $0.derivationIndex == index }
    }

    func handedOffCoins() async throws -> [OwnAsset] {
        try await handedOffCoinModels().map { .coin($0.derivationIndex) }
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
