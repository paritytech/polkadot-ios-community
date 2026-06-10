import Foundation
import Operation_iOS
import SubstrateSdk

protocol RuntimeSyncServiceProtocol {
    func register(chain: ChainModel, with connection: ChainConnection)
    func unregisterIfExists(chainId: ChainModel.Id)
    func apply(version: RuntimeVersion, for chainId: ChainModel.Id)

    func hasChain(with chainId: ChainModel.Id) -> Bool
    func isChainSyncing(_ chainId: ChainModel.Id) -> Bool
}

enum RuntimeSyncServiceError: Error {
    case skipMetadataUnchanged
}

final class RuntimeSyncService {
    struct SyncInfo {
        let typesURL: URL?
        let connection: JSONRPCEngine
    }

    struct SyncResult {
        let chainId: ChainModel.Id
        let typesSyncResult: Result<String, Error>?
        let metadataSyncResult: Result<Void, Error>?
        let runtimeVersion: RuntimeVersion?
    }

    struct RetryAttempt {
        let chainId: ChainModel.Id
        let shouldSyncTypes: Bool
        let runtimeVersion: RuntimeVersion?
        let attempt: Int
    }

    let repository: AnyDataProviderRepository<RuntimeMetadataItem>
    let filesOperationFactory: RuntimeFilesOperationFactoryProtocol
    let dataOperationFactory: DataOperationFactoryProtocol
    let runtimeFetchFactory: RuntimeFetchOperationFactoryProtocol
    let runtimeLocalMigrator: RuntimeLocalMigrating
    let eventCenter: EventCenterProtocol
    let retryStrategy: ReconnectionStrategyProtocol
    let operationQueue: OperationQueue
    let dataHasher: StorageHasher
    let logger: LoggerProtocol?
    let rpcTimeout: Int

    var knownChains: [ChainModel.Id: SyncInfo] = [:]
    var syncingChains: [ChainModel.Id: CompoundOperationWrapper<SyncResult>] = [:]
    var retryAttempts: [ChainModel.Id: RetryAttempt] = [:]
    var mutex = NSLock()
    var retryScheduler: Scheduler?

    init(
        repository: AnyDataProviderRepository<RuntimeMetadataItem>,
        runtimeFetchFactory: RuntimeFetchOperationFactoryProtocol,
        runtimeLocalMigrator: RuntimeLocalMigrating,
        filesOperationFactory: RuntimeFilesOperationFactoryProtocol,
        dataOperationFactory: DataOperationFactoryProtocol,
        eventCenter: EventCenterProtocol,
        operationQueue: OperationQueue,
        retryStrategy: ReconnectionStrategyProtocol = ExponentialReconnection(),
        dataHasher: StorageHasher = .twox256,
        rpcTimeout: Int = Int(UInt16.max),
        logger: LoggerProtocol? = nil
    ) {
        self.repository = repository
        self.runtimeFetchFactory = runtimeFetchFactory
        self.runtimeLocalMigrator = runtimeLocalMigrator
        self.filesOperationFactory = filesOperationFactory
        self.dataOperationFactory = dataOperationFactory
        self.retryStrategy = retryStrategy
        self.eventCenter = eventCenter
        self.dataHasher = dataHasher
        self.rpcTimeout = rpcTimeout
        self.logger = logger
        self.operationQueue = operationQueue
    }

    func clearOperations(for chainId: ChainModel.Id) {
        if let existingOperation = syncingChains[chainId] {
            syncingChains[chainId] = nil
            existingOperation.cancel()
        }

        retryAttempts[chainId] = nil
    }
}

extension RuntimeSyncService: SchedulerDelegate {
    func didTrigger(scheduler _: SchedulerProtocol) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        retryScheduler = nil

        for requestKeyValue in retryAttempts where syncingChains[requestKeyValue.key] == nil {
            performSync(
                for: requestKeyValue.key,
                shouldSyncTypes: requestKeyValue.value.shouldSyncTypes,
                newVersion: requestKeyValue.value.runtimeVersion
            )
        }
    }
}
