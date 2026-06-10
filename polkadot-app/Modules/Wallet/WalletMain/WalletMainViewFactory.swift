import Foundation
import Keystore_iOS
import SubstrateSdk

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

        let launcher = W3sPayLauncher(
            coinageService: context.coinageService,
            chainRegistry: chainRegistry,
            logger: Logger.shared
        )
        let dsfinvkRouter = W3sDsfinvkRouter(
            remoteConfig: FirebaseFacade.shared,
            launcher: launcher,
            logger: Logger.shared
        )

        let presenter = WalletMainPresenter(
            wireframe: wireframe,
            dsfinvkRouter: dsfinvkRouter,
            collectiblesURLProvider: CollectiblesURLProvider.makeDefault()
        )

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
