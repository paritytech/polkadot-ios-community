import Foundation
import Keystore_iOS
import SubstrateSdk
import ChainRegistry

@MainActor
enum WalletMainViewFactory {
    static func createView(
        with context: WalletFlowContextProtocol,
        chainAssetId: ChainAssetId
    ) -> WalletMainViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry

        let wallet = SelectedWallet.main
        guard
            let chain = chainRegistry.getChain(for: chainAssetId.chainId),
            let chainAsset = chain.chainAsset(for: chainAssetId.assetId)
        else {
            return nil
        }
        let wireframe = WalletMainWireframe(personDataStore: context.personDataStore)

        let networkStatusObserver = NetworkStatusObserver(
            networkStatusService: context.networkStatusService,
            chainIds: [chainAssetId.chainId],
            logger: Logger.shared
        )

        let interactor = WalletMainInteractor(
            collectiblesURLProvider: CollectiblesURLProvider.makeDefault(),
            networkStatusObserver: networkStatusObserver
        )

        let presenter = WalletMainPresenter(
            interactor: interactor,
            wireframe: wireframe,
            titleViewModelFactory: NetworkStatusTitleViewModelFactory(
                screenTitle: String(localized: .walletMainTitle)
            )
        )
        interactor.presenter = presenter

        let view = WalletMainViewController(
            presenter: presenter,
            assetDetailsScene:
            AssetDetailsViewFactory.createEmbeddedScene(
                context: context,
                chainAsset: chainAsset
            ),
            identityDetailsScene:
            IdentityDetailsViewFactory.createEmbeddedScene(
                chainModel: chainAsset.chain,
                wallet: wallet,
                personDataStore: context.personDataStore
            )
        )
        presenter.view = view

        return view
    }
}
