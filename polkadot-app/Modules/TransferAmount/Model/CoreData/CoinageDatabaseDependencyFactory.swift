import AsyncExtensions
import Foundation
import Operation_iOS
import Coinage
@preconcurrency import SDKLogger
import StructuredConcurrency

// @unchecked: dependencies are effectively immutable + thread-safe; protocols not yet Sendable-annotated
struct CoinageDatabaseDependencyFactory: DatabaseDependencyFactoring, @unchecked Sendable {
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

    func makeTrackedCoinRepository() -> AnyDataProviderRepository<TrackedCoin> {
        let mapper = TrackedCoinMapper()
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

    func makeTrackedVoucherRepository() -> AnyDataProviderRepository<TrackedVoucher> {
        let mapper = TrackedVoucherMapper()
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

    func makeTrackedCoinSnapshotStream() -> AnyAsyncSequence<[TrackedCoin]> {
        storageFacade.databaseService.subscribeSnapshot(
            mapper: AnyCoreDataMapper(TrackedCoinMapper())
        )
    }

    func makeTrackedVoucherSnapshotStream() -> AnyAsyncSequence<[TrackedVoucher]> {
        storageFacade.databaseService.subscribeSnapshot(
            mapper: AnyCoreDataMapper(TrackedVoucherMapper())
        )
    }
}
