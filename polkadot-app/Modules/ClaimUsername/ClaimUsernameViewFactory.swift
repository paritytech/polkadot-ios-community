import Foundation
import Common
import Keystore_iOS
import ExtrinsicService
import KeyDerivation

enum ClaimUsernameViewFactory {
    static func createLiteClaimView(
        observer: RootStateObserving
    ) -> ClaimUsernameViewProtocol? {
        guard let hasWallets = try? RootEntropyManager.shared.hasRootEntropy() else {
            return nil
        }

        guard let interactor = createLiteInteractor(hasWallets: hasWallets) else {
            return nil
        }

        let wireframe = ClaimLiteUsernameWireframe(observer: observer)

        let validationFactory = UsernameValidationFactory(presentable: wireframe)
        let presenter = ClaimUsernamePresenter(
            interactor: interactor,
            wireframe: wireframe,
            validationFactory: validationFactory,
            viewModelProvider: ClaimUsernameViewModelFactory(
                recoverable: !hasWallets,
                full: false
            ),
            prefilledUsername: nil,
            logger: Logger.shared
        )

        let view = ClaimLiteUsernameViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter
        validationFactory.view = view

        return view
    }

    static func createFullClaimView(
        registeredData: People.RegisteredData
    ) -> ClaimUsernameViewProtocol? {
        guard let interactor = createFullInteractor(registeredData: registeredData) else {
            return nil
        }

        let wireframe = ClaimFullUsernameWireframe()

        let validationFactory = UsernameValidationFactory(presentable: wireframe)
        let presenter = ClaimUsernamePresenter(
            interactor: interactor,
            wireframe: wireframe,
            validationFactory: validationFactory,
            viewModelProvider: ClaimUsernameViewModelFactory(
                recoverable: false,
                full: true
            ),
            prefilledUsername: registeredData.liteUsername,
            logger: Logger.shared
        )

        let view = ClaimFullUsernameViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter
        validationFactory.view = view

        return view
    }

    private static func createLiteInteractor(hasWallets: Bool) -> ClaimLiteUsernameInteractor? {
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let dependencies = ClaimLiteUsernameDependency(
            walletSetupManagerFactory: { createWalletManager() },
            registrationParamsFactory: { mainWallet in
                try LitePersonParamsFactory(
                    mainWallet: mainWallet,
                    liteVrfManager: BandersnatchKeyManager.litePerson(),
                    chatEncryptorManager: ChatEncryptionManager()
                )
            },
            usernameOperationFactory: { UsernameOperationFactory(tokenProvider: JWTTokenManager.shared) },
            usernameStorage: { UsernameStorage() },
            operationQueue: { operationQueue },
            mainWallet: SelectedWallet.main
        )

        return ClaimLiteUsernameInteractor(
            walletCreated: hasWallets,
            dependencies: dependencies,
            logger: Logger.shared
        )
    }

    private static func createWalletManager() -> WalletSetupManaging {
        WalletSetupManager(
            mnemonicGenerator: IRMnemonicCreator(),
            mnemonicBackupHelper: MnemonicBackupHelper(),
            entropyManager: RootEntropyManager.shared,
            logger: Logger.shared
        )
    }

    private static func createFullInteractor(
        registeredData: People.RegisteredData
    ) -> ClaimFullUsernameInteractor? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let logger = Logger.shared

        let extrinsicSubmissionFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: operationQueue,
            logger: logger
        )

        guard
            let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain),
            let extrinsicSubmitMonitor = try? extrinsicSubmissionFacade.createMonitorFactory(chain: chain)
        else {
            return nil
        }

        let litePersonOriginFactory = PersonLiteOriginFactory(
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )

        let fullVRFManager = BandersnatchKeyManager.fullPerson()

        let gameExtrinsicOriginFactory = PersonhoodOriginFactory(
            vrfManager: fullVRFManager,
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )

        let claimService = FullUsernameClaimService(
            chain: chain,
            registeredData: registeredData,
            extrinsicSubmitMonitor: extrinsicSubmitMonitor,
            extrinsicOriginFactory: gameExtrinsicOriginFactory,
            litePersonOriginFactory: litePersonOriginFactory
        )

        return ClaimFullUsernameInteractor(
            registeredData: registeredData,
            claimService: claimService
        )
    }
}
