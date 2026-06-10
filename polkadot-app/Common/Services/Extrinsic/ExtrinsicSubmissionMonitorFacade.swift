import Foundation
import ExtrinsicService
import SubstrateSdk
import SubstrateStorageQuery
import AssetExchange
import Operation_iOS

protocol ExtrinsicSubmissionMonitorFacadeProtocol {
    func createMonitorFactory(chain: ChainProtocol) throws -> ExtrinsicSubmitMonitorFactoryProtocol
}

final class ExtrinsicSubmissionMonitorFacade {
    let chainRegistry: ChainRegistryProtocol
    let operationQueue: OperationQueue
    let extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol
    let logger: LoggerProtocol

    init(
        extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol,
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.chainRegistry = chainRegistry
        self.extrinsicServiceFactory = extrinsicServiceFactory
        self.operationQueue = operationQueue
        self.logger = logger
    }

    convenience init(
        chainRegistry: ChainRegistryProtocol,
        substrateStorageFacade: StorageFacadeProtocol,
        operationQueue: OperationQueue,
        extrinsicVersion: Extrinsic.Version = .V5(extensionVersion: 0),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.init(
            extrinsicServiceFactory: ExtrinsicServiceFactory(
                chainRegistry: chainRegistry,
                substrateStorageFacade: substrateStorageFacade,
                customFeeEstimator: ExtrinsicCustomFeeEstimatorFactory(providers: []),
                transactionExtensionFactory: ExtrinsicTransactionExtensionFactory(),
                extrinsicVersion: extrinsicVersion,
                operationQueue: operationQueue,
                logger: logger
            ),
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

extension ExtrinsicSubmissionMonitorFacade: ExtrinsicSubmissionMonitorFacadeProtocol {
    func createMonitorFactory(chain: ChainProtocol) throws -> ExtrinsicSubmitMonitorFactoryProtocol {
        let connection = try chainRegistry.getConnectionOrError(for: chain.chainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chain.chainId)

        let extrinsicService = try extrinsicServiceFactory.createExtrinsicService(
            chain: chain
        )

        let statusService = ExtrinsicStatusService(
            connection: connection,
            runtimeProvider: runtimeProvider,
            eventsQueryFactory: BlockEventsQueryFactory(
                operationQueue: operationQueue,
                eventsRepository: SubstrateEventsRepository(),
                storageRequestFactory: StorageRequestFactory(
                    remoteFactory: StorageKeyFactory(),
                    operationManager: OperationManager(operationQueue: operationQueue)
                ),
                logger: logger
            )
        )

        return ExtrinsicSubmissionMonitorFactory(
            submissionService: extrinsicService,
            statusService: statusService,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}
