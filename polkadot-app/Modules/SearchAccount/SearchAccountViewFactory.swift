import Foundation
import Coinage
import ChainRegistry
import MessageExchangeKit

@MainActor
enum SearchAccountViewFactory {
    static func createView(
        for chainAsset: ChainAsset,
        coinageServicing: CoinageServicing
    ) -> SearchAccountViewProtocol? {
        let logger = Logger.shared
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let recentContactsService = RecentContactsService(
            recentContactsSubscriptionFactory: RecentContactsSubscriptionFactory.shared,
            identityQueryFactory: IdentityPalletQueryFactory(
                operationQueue: operationQueue
            ),
            chainRegistry: chainRegistry,
            usernameChainId: AppConfig.Chains.usernameChain,
            operationQueue: operationQueue,
            logger: logger
        )
        let searchUsernameFactory = SearchUsernameFactory(
            chatContactRepositoryFactory: ChatContactRepositoryFactory(),
            chainModel: chainAsset.chain
        )
        let recipientViewModelFactory = RecipientViewModelFactory()
        let interactor = SearchAccountInteractor(
            searchUsernameFactory: searchUsernameFactory,
            recentContactsManager: recentContactsService,
            remoteContactSearch: RemoteContactOperationFactory(),
            chatOpenResolver: ChatOpenModelResolver(),
            chainAsset: chainAsset,
            logger: logger
        )
        let wireframe = SearchAccountWireframe(coinageServicing: coinageServicing)
        let presenter = SearchAccountPresenter(
            interactor: interactor,
            wireframe: wireframe,
            recipientViewModelFactory: recipientViewModelFactory,
            chainAsset: chainAsset
        )

        let view = SearchAccountViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
