import Foundation
import Foundation_iOS
import Individuality
import KeyDerivation
import Products

enum Web3SummitSpaViewFactory {
    @MainActor
    static func createView(observer: RootStateObserving) -> Web3SummitSpaViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry

        let accountManager = ProductsAccountManager(
            entropyManager: RootEntropyManager.shared,
            allowanceSupport: nil
        )

        guard
            let config = try? AppConfig.getWeb3Summit(),
            let productPage = ProductPage.fromUrl(config.dotNsUrl),
            let dotNsHost = config.dotNsUrl.host(),
            let flowState = SPAFlowState.create(),
            let peopleConnection = try? chainRegistry.getConnectionOrError(for: AppConfig.Chains.usernameChain),
            let peopleRuntime = try? chainRegistry.getRuntimeProviderOrError(for: AppConfig.Chains.usernameChain)
        else {
            return nil
        }

        let spaConfiguration = SPAConfiguration(
            title: nil,
            isRootScreen: false,
            showMoreButton: false,
            page: productPage
        )

        guard let spaView = SPAViewFactory.createView(configuration: spaConfiguration, flowState: flowState) else {
            return nil
        }

        let contractRepository = Web3SummitContractRepository(
            reviveCaller: ReviveContractCaller(),
            chainRegistry: chainRegistry,
            config: config
        )

        let membershipStatusChecker = MembershipStatusChecker(
            connection: peopleConnection,
            runtimeCodingService: peopleRuntime
        )

        let interactor = Web3SummitSpaInteractor(
            accountManager: accountManager,
            contractRepository: contractRepository,
            membershipStatusChecker: membershipStatusChecker,
            liteVrfManager: BandersnatchKeyManager.litePerson(),
            verifiedStorage: Web3SummitVerifiedStorage(),
            dotNsHost: dotNsHost,
            logger: Logger.shared
        )

        let gate = Web3SummitGate.makeDefault()
        let wireframe = Web3SummitSpaWireframe(observer: observer)
        let presenter = Web3SummitSpaPresenter(
            interactor: interactor,
            wireframe: wireframe,
            isSkippable: gate.isSkippable,
            logger: Logger.shared
        )

        let view = Web3SummitSpaViewController(
            presenter: presenter,
            spaController: spaView.controller
        )
        presenter.view = view

        return view
    }
}
