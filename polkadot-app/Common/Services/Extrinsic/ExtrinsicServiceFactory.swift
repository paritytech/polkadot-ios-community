import Foundation
import Operation_iOS
import Keystore_iOS
import SubstrateSdk
import SubstrateSdkExt
import SubstrateMetadataHash
import ExtrinsicService
import ExtrinsicServiceExt
import ChainRegistry

protocol ExtrinsicServiceCreating: ExtrinsicServiceFactoryProtocol {
    func createExtrinsicService(
        chain: ChainProtocol,
        submitter: ExtrinsicSubmitting?
    ) throws -> ExtrinsicServiceProtocol
}

final class ExtrinsicServiceFactory {
    private let chainRegistry: ChainRegistryProtocol
    private let operationQueue: OperationQueue
    private let metadataHashOperationFactory: MetadataHashOperationFactoryProtocol
    private let customFeeEstimator: ExtrinsicCustomFeeEstimatingFactoryProtocol
    private let transactionExtensionFactory: ExtrinsicTransactionExtensionMaking
    private let extrinsicVersion: Extrinsic.Version
    private let logger: LoggerProtocol

    init(
        chainRegistry: ChainRegistryProtocol,
        substrateStorageFacade: StorageFacadeProtocol,
        customFeeEstimator: ExtrinsicCustomFeeEstimatingFactoryProtocol,
        transactionExtensionFactory: ExtrinsicTransactionExtensionMaking,
        extrinsicVersion: Extrinsic.Version = .V5(extensionVersion: 0),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chainRegistry = chainRegistry

        let metadataItemProvider = RuntimeMetadataItemProvider(
            runtimeMetadataRepositoryFactory: RuntimeMetadataRepositoryFactory(storageFacade: substrateStorageFacade)
        )

        metadataHashOperationFactory = MetadataHashOperationFactory(
            metadataItemProvider: metadataItemProvider,
            operationQueue: operationQueue
        )

        self.operationQueue = operationQueue
        self.extrinsicVersion = extrinsicVersion
        self.customFeeEstimator = customFeeEstimator
        self.transactionExtensionFactory = transactionExtensionFactory
        self.logger = logger
    }
}

extension ExtrinsicServiceFactory: ExtrinsicServiceCreating {
    func createExtrinsicService(chain: ChainProtocol) throws -> ExtrinsicServiceProtocol {
        try createExtrinsicService(chain: chain, submitter: nil)
    }

    func createExtrinsicService(
        chain: ChainProtocol,
        submitter: ExtrinsicSubmitting?
    ) throws -> ExtrinsicServiceProtocol {
        let connection = try chainRegistry.getConnectionOrError(for: chain.chainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chain.chainId)
        let chainModel = try chainRegistry.getChainOrError(for: chain.chainId)

        let host = ExtrinsicFeeEstimatorHost(
            chain: chain,
            connection: connection,
            runtimeProvider: runtimeProvider,
            operationQueue: operationQueue,
            logger: logger
        )

        let feeEstimatingFactory = ExtrinsicFeeEstimatingWrapperFactory(
            host: host,
            customFeeEstimatorFactory: customFeeEstimator
        )

        return try ExtrinsicService(
            chain: chain,
            extrinsicVersion: extrinsicVersion,
            runtimeRegistry: runtimeProvider,
            feeEstimationRegistry: ExtrinsicFeeEstimationRegistry(
                chain: chain,
                estimatingWrapperFactory: feeEstimatingFactory,
                feeInstallingWrapperFactory: ExtrinsicFeeInstallingFactory(host: host)
            ),
            metadataHashOperationFactory: metadataHashOperationFactory,
            eraOperationFactory: MortalEraOperationFactory(chain: chainModel),
            extensions: transactionExtensionFactory.createExtensions(),
            engine: connection,
            operationQueue: operationQueue,
            timeout: JSONRPCTimeout.hour,
            submitter: submitter ?? makeForkProtectedSubmitter(chain: chain)
        )
    }

    func createOperationFactory(chain: ChainProtocol) throws -> ExtrinsicOperationFactoryProtocol {
        let connection = try chainRegistry.getConnectionOrError(for: chain.chainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chain.chainId)
        let chainModel = try chainRegistry.getChainOrError(for: chain.chainId)

        let host = ExtrinsicFeeEstimatorHost(
            chain: chain,
            connection: connection,
            runtimeProvider: runtimeProvider,
            operationQueue: operationQueue,
            logger: logger
        )

        let feeEstimatingFactory = ExtrinsicFeeEstimatingWrapperFactory(
            host: host,
            customFeeEstimatorFactory: customFeeEstimator
        )

        return ExtrinsicOperationFactory(
            chain: chain,
            extrinsicVersion: extrinsicVersion,
            feeEstimationRegistry: ExtrinsicFeeEstimationRegistry(
                chain: chain,
                estimatingWrapperFactory: feeEstimatingFactory,
                feeInstallingWrapperFactory: ExtrinsicFeeInstallingFactory(host: host)
            ),
            runtimeRegistry: runtimeProvider,
            customExtensions: transactionExtensionFactory.createExtensions(),
            engine: connection,
            metadataHashOperationFactory: metadataHashOperationFactory,
            eraOperationFactory: MortalEraOperationFactory(chain: chainModel),
            operationQueue: operationQueue,
            timeout: JSONRPCTimeout.singleNode
        )
    }
}

private extension ExtrinsicServiceFactory {
    func makeForkProtectedSubmitter(chain: ChainProtocol) throws -> ExtrinsicSubmitting {
        let base = try DefaultExtrinsicSubmitter(
            operationFactory: createOperationFactory(chain: chain),
            operationQueue: operationQueue,
            timeout: JSONRPCTimeout.hour
        )

        return ValidatingExtrinsicSubmitterFactory.makeResubmittingSubmitter(
            base: base,
            chainId: chain.chainId,
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            maxAttempts: 10,
            logger: logger
        )
    }
}
