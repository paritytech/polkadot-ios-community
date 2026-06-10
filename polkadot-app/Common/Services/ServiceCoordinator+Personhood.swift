import Foundation
import Keystore_iOS
import Operation_iOS
import SubstrateSdk
import Individuality
import CommonService
import KeyDerivation
import SubstrateOperation

extension ServiceCoordinator {
    struct PersonhoodServices {
        let backgroundService: PersonhoodBackgroundService
        let registrationService: PersonhoodRegistrationServicing
    }

    static func createPersonhoodServices(
        syncStateStore: DetermineStateSyncStore
    ) -> PersonhoodServices? {
        let vrfManager = BandersnatchKeyManager.fullPerson()
        guard let candidateAccountId = try? SelectedWallet.candidate.getRawPublicKey(),
              let chain = try? ChainRegistryFacade.sharedRegistry.getChainOrError(
                  for: AppConfig.Chains.usernameChain
              ) else {
            return nil
        }

        let operationFactory = PersonhoodRegistrationOperationFactory(
            accountId: candidateAccountId,
            vrfManager: vrfManager
        )

        let extrinsicSubmissionMonitor = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: Logger.shared
        )

        let selfIncludeSubmissionService = PersonSelfIncludeSubmissionService(
            chain: chain,
            operationFactory: operationFactory,
            extrinsicSubmissionFacade: extrinsicSubmissionMonitor
        )

        let registrationService = createPersonhoodRegistrationService(
            chain: chain,
            vrfManager: vrfManager,
            operationFactory: operationFactory,
            selfIncludeSubmissionService: selfIncludeSubmissionService
        )

        guard
            let backgroundService = createPersonRegistrationBackgroundService(),
            let selfIncludeBackgroundService = createPersonSelfIncludeBackgroundService(
                submitter: selfIncludeSubmissionService
            )
        else {
            return nil
        }

        let notificationService = PersonRegistrationNotificationService(
            localNotificationService: UserNotificationService.shared
        )

        let personhoodBackgroundService = PersonhoodBackgroundService(
            personhoodRegistrationService: registrationService,
            syncStateStore: syncStateStore,
            backgroundService: backgroundService,
            selfIncludeBackgroundService: selfIncludeBackgroundService,
            notificationService: notificationService
        )

        return PersonhoodServices(
            backgroundService: personhoodBackgroundService,
            registrationService: registrationService
        )
    }
}

private extension ServiceCoordinator {
    static func createPersonhoodRegistrationService(
        chain: ChainProtocol,
        vrfManager: BandersnatchKeyManaging,
        operationFactory: PersonhoodRegistrationOperationMaking,
        selfIncludeSubmissionService: SelfIncludeSubmitting
    ) -> PersonhoodRegistrationService {
        PersonhoodRegistrationService(
            chain: chain,
            candidateWallet: SelectedWallet.candidate,
            mobRuleWallet: SelectedWallet.mobRuleAlias,
            scoreWallet: SelectedWallet.scoreAlias,
            resourcesWallet: SelectedWallet.resourcesAlias,
            vrfManager: vrfManager,
            blockNumberOperationFactory: BlockNumberOperationFactory(
                chainRegistry: ChainRegistryFacade.sharedRegistry,
                operationQueue: OperationManagerFacade.sharedDefaultQueue
            ),
            operationFactory: operationFactory,
            candidateOriginFactory: ExtrinsicOriginFactory.personCandidate(),
            personhoodOriginFactory: PersonhoodOriginFactory(
                vrfManager: vrfManager,
                chainRegistry: ChainRegistryFacade.sharedRegistry,
                operationQueue: OperationManagerFacade.sharedDefaultQueue,
                logger: Logger.shared
            ),
            selfIncludeSubmissionService: selfIncludeSubmissionService
        )
    }

    static func createPersonRegistrationBackgroundService() -> PersonRegistrationBackgroundServiceProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain),
              let runtimeProvider = chainRegistry.getRuntimeProvider(for: AppConfig.Chains.usernameChain) else {
            return nil
        }

        let logger = Logger.shared

        let connectionFactory = ConnectionFactory(
            logger: logger,
            operationQueue: OperationManagerFacade.runtimeSyncQueue
        )

        let queryFactory = PersonRegistrationQueryFactory(
            operationQueue: OperationManagerFacade.sharedDefaultQueue
        )

        let vrfManager = BandersnatchKeyManager.fullPerson()

        let fetcher = PersonRegistrationStateFetcher(
            mobRuleWallet: SelectedWallet.mobRuleAlias,
            scoreWallet: SelectedWallet.scoreAlias,
            resourcesWallet: SelectedWallet.resourcesAlias,
            vrfManager: vrfManager,
            chain: chain,
            runtimeProvider: runtimeProvider,
            connectionFactory: connectionFactory,
            queryFactory: queryFactory,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: logger
        )

        return PersonRegistrationBackgroundService(
            fetcher: fetcher,
            logger: logger
        )
    }

    static func createPersonSelfIncludeBackgroundService(
        submitter: SelfIncludeSubmitting
    ) -> PersonSelfIncludeBackgroundServiceProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard
            let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: AppConfig.Chains.usernameChain)
        else {
            return nil
        }

        let connectionFactory = ConnectionFactory(
            logger: Logger.shared,
            operationQueue: OperationManagerFacade.runtimeSyncQueue
        )

        let vrfManager = BandersnatchKeyManager.fullPerson()

        let fetcher = PersonSelfIncludeStateFetcher(
            vrfManager: vrfManager,
            chain: chain,
            runtimeProvider: runtimeProvider,
            connectionFactory: connectionFactory,
            logger: Logger.shared
        )

        return PersonSelfIncludeBackgroundService(
            fetcher: fetcher,
            submitter: submitter,
            logger: Logger.shared
        )
    }
}
