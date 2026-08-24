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
    private let markRepository: AnyDataProviderRepository<HandoffMark>
    private let transacting: any CoinageTransacting

    init(storageFacade: StorageFacadeProtocol, transacting: any CoinageTransacting) {
        let entryRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDDurabilityEntry.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(DurabilityEntryMapper())
        )
        repository = AnyDataProviderRepository(entryRepository)

        let marks = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(HandoffMarkMapper())
        )
        markRepository = AnyDataProviderRepository(marks)
        self.transacting = transacting
    }
}

// MARK: - Registration

extension DurabilityCoreDataStore {
    func register(_ entry: DurabilityEntry) async throws {
        try await transacting.withTransaction { tx in
            let inputIds = Set(entry.inputs.map(\.identifier))
            let outputIds = Set(entry.outputs.map(\.identifier))

            let claimedInputs = try tx.claimedInputIdentifiers(among: inputIds)
            let mintedOutputs = try tx.mintedOutputIdentifiers(among: outputIds)
            let receivedInputs = try tx.receivedInputIdentifiers(among: outputIds)
            let marks = try tx.markedIdentifiers(among: inputIds)

            try RegistrationValidator.validate(
                entry,
                claimedInputs: claimedInputs,
                mintedOutputs: mintedOutputs,
                receivedInputs: receivedInputs,
                marks: marks
            )

            var sequenced = entry
            sequenced.sequence = try tx.nextSequence()

            try tx.upsert(sequenced)
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

    private func write<Value>(
        _ id: TransactionId,
        _ field: WritableKeyPath<DurabilityEntry, Value>,
        _ value: Value
    ) async throws {
        guard var entry = try await fetch(id: id) else {
            throw DurabilityError.entryNotFound(id)
        }
        entry[keyPath: field] = value
        try await repository.saveOperation({ [entry] }, { [] }).asyncExecute()
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

    func minter(of asset: OwnAsset) async throws -> DurabilityEntry? {
        let identifier = asset.identifier
        return try await fetchAll().first { entry in
            entry.outputs.contains { $0.identifier == identifier }
        }
    }

    func consumers(of input: Input) async throws -> [DurabilityEntry] {
        let identifier = input.identifier
        return try await fetchAll().filter { entry in
            entry.inputs.contains { $0.identifier == identifier }
        }
    }
}

// MARK: - Handoff marks

extension DurabilityCoreDataStore {
    func markHandedOff(_ asset: OwnAsset) async throws {
        try await transacting.withTransaction { try $0.insertMark(asset) }
    }

    func hasEverBeenHandedOff(_ asset: OwnAsset) async throws -> Bool {
        let identifier = asset.identifier
        return try await fetchMarks().contains { $0.identifier == identifier }
    }

    func handedOffCoins() async throws -> [OwnAsset] {
        try await fetchMarks().compactMap { AssetCoding.ownAsset(from: $0.identifier) }
    }

    private func fetchMarks() async throws -> [HandoffMark] {
        try await markRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }
}
