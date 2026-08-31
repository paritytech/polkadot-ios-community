import Foundation
import Operation_iOS
import Products

/// CoreData-backed persistence for open worker operations, in the shared
/// `UserDataModel` store behind the `CDProductOperation` entity.
///
/// Records are a process-lifetime keep-alive log: nothing keeps a worker alive
/// across a relaunch, so `ProductWorkerOperationService.resetForNewSession`
/// clears the table on launch. They are persisted so an interface can list open
/// operations later.
final class CoreDataProductOperationStore: ProductOperationStoring, @unchecked Sendable {
    private let repository: AnyDataProviderRepository<ProductOperationRecord>

    init(storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared) {
        repository = AnyDataProviderRepository(
            storageFacade.createRepository(mapper: AnyCoreDataMapper(ProductOperationMapper()))
        )
    }

    func save(_ record: ProductOperationRecord) async throws {
        try await repository.saveOperation({ [record] }, { [] }).asyncExecute()
    }

    func delete(productId: ProductId, id: UInt32) async throws {
        let identifier = ProductOperationRecord.identifier(productId: productId, id: id)
        try await repository.saveOperation({ [] }, { [identifier] }).asyncExecute()
    }

    func all() async throws -> [ProductOperationRecord] {
        try await repository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }

    func clearAll() async throws {
        try await repository.deleteAllOperation().asyncExecute()
    }
}
