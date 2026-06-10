import Foundation
import Operation_iOS
import Individuality

final class AllowanceRepositoryFactory {
    private let storageFacade: StorageFacadeProtocol

    init(storageFacade: StorageFacadeProtocol) {
        self.storageFacade = storageFacade
    }

    func createRepository() -> AnyDataProviderRepository<AllowanceRecord> {
        AnyDataProviderRepository(
            storageFacade.createRepository(
                filter: nil,
                sortDescriptors: [],
                mapper: AnyCoreDataMapper(AllowanceRecordMapper())
            )
        )
    }
}
