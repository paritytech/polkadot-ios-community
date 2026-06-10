import Coinage
import CoreData
import Foundation
import Operation_iOS

/// CoreData-backed implementation of ``TransferWALStoring``.
///
/// Persists WAL entries as `CDTransferWALEntry` entities.
/// Mirrors `ClaimPlanCoreDataStore` pattern.
final class TransferWALCoreDataStore: TransferWALStoring, @unchecked Sendable {
    private let repository: AnyDataProviderRepository<TransferWALEntry>
    private let updateRepository: AnyDataProviderRepository<TransferWALEntry>

    init(storageFacade: StorageFacadeProtocol) {
        let mapper = TransferWALMapper()
        let coreDataRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        repository = AnyDataProviderRepository(coreDataRepository)

        let updateMapper = TransferWALUpdateMapper()
        let updateCoreDataRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(updateMapper)
        )
        updateRepository = AnyDataProviderRepository(updateCoreDataRepository)
    }

    func save(_ entry: TransferWALEntry) async throws {
        try await repository.saveOperation({ [entry] }, { [] }).asyncExecute()
    }

    func save(contentsOf entries: [TransferWALEntry]) async throws {
        guard !entries.isEmpty else { return }
        try await repository.saveOperation({ entries }, { [] }).asyncExecute()
    }

    func update(id: UUID, checkpointBlock: CheckpointBlock) async throws {
        let entry = TransferWALEntry(
            id: id,
            inputCoinIds: [],
            inputVoucherIds: [],
            expectedCoinIndices: [],
            checkpointBlock: checkpointBlock,
            mortality: 0,
            createdAt: .distantPast
        )
        // Update repository will update ONLY hash and block info
        try await updateRepository.saveOperation({ [entry] }, { [] }).asyncExecute()
    }

    func fetchAll() async throws -> [TransferWALEntry] {
        try await repository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }

    func delete(id: UUID) async throws {
        try await repository.saveOperation({ [] }, { [id.uuidString] }).asyncExecute()
    }
}
