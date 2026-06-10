import Foundation
import Operation_iOS
import Coinage

struct CoinageDatabaseDependencyFactory: DatabaseDependencyFactoring {
    private let storageFacade: StorageFacadeProtocol
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    init(
        storageFacade: StorageFacadeProtocol,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.storageFacade = storageFacade
        self.operationQueue = operationQueue
        self.logger = logger
    }

    func makeCoinRepository() -> AnyDataProviderRepository<Coin> {
        let mapper = CoinMapper()
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        return AnyDataProviderRepository(repository)
    }

    func makeCoinStateRepository() -> AnyDataProviderRepository<Coin> {
        let mapper = CoinStateMapper()
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        return AnyDataProviderRepository(repository)
    }

    func makeVoucherRepository() -> AnyDataProviderRepository<Voucher> {
        let mapper = VoucherMapper()
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        return AnyDataProviderRepository(repository)
    }

    func makeVoucherLocationRepository() -> AnyDataProviderRepository<Voucher> {
        let mapper = VoucherLocationMapper()
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        return AnyDataProviderRepository(repository)
    }

    func makeCoinProvider() -> StreamableProvider<Coin> {
        let mapper = AnyCoreDataMapper(CoinMapper())

        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: mapper
        )

        let repositoryObservable = CoreDataContextObservable(
            service: storageFacade.databaseService,
            mapper: mapper,
            predicate: { _ in true }
        )

        repositoryObservable.start { [logger] error in
            if let error {
                logger.error("Did receive error: \(error)")
            }
        }

        let source = AnyStreamableSource(EmptyStreamableSource<Coin>())

        return StreamableProvider(
            source: source,
            repository: AnyDataProviderRepository(repository),
            observable: AnyDataProviderRepositoryObservable(repositoryObservable),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }

    func makeVoucherProvider() -> StreamableProvider<Voucher> {
        let mapper = AnyCoreDataMapper(VoucherMapper())

        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: mapper
        )

        let repositoryObservable = CoreDataContextObservable(
            service: storageFacade.databaseService,
            mapper: mapper,
            predicate: { _ in true }
        )

        repositoryObservable.start { [logger] error in
            if let error {
                logger.error("Did receive error: \(error)")
            }
        }

        let source = AnyStreamableSource(EmptyStreamableSource<Voucher>())

        return StreamableProvider(
            source: source,
            repository: AnyDataProviderRepository(repository),
            observable: AnyDataProviderRepositoryObservable(repositoryObservable),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }
}
