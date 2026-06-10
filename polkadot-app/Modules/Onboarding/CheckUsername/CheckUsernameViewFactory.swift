import Foundation
import Keystore_iOS
import NovaCrypto

enum CheckUsernameViewFactory {
    static func createView(with observer: RootStateObserving) -> CheckUsernameViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let chainId = AppConfig.Chains.usernameChain

        let identityService = IdentityService(
            chainRegistry: chainRegistry,
            chain: chainId,
            operationQueue: operationQueue,
            logger: Logger.shared
        )

        let interactor = CheckUsernameInteractor(
            selectedWallet: SelectedWallet.main,
            identityService: identityService,
            settingsManager: SettingsManager.shared
        )

        let wireframe = CheckUsernameWireframe(observer: observer)
        let presenter = CheckUsernamePresenter(interactor: interactor, wireframe: wireframe)
        let view = CheckUsernameViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
