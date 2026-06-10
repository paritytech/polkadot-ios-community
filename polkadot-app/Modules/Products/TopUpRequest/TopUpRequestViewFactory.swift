import Coinage
import Foundation
import SubstrateSdk

@MainActor
enum TopUpRequestViewFactory {
    static func createView(
        context: TopUpRequestContext,
        coinageService: any CoinageServicing
    ) -> TopUpRequestViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let chainAssetId = AppConfig.Assets.mainAsset

        guard
            let chain = chainRegistry.getChain(for: chainAssetId.chainId),
            let chainAsset = chain.chainAsset(for: chainAssetId.assetId)
        else {
            return nil
        }

        let interactor = TopUpRequestInteractor(
            context: context,
            coinageService: coinageService,
            logger: Logger.shared
        )
        let wireframe = TopUpRequestWireframe()
        let viewModelFactory = TopUpRequestViewModelFactory(chainAsset: chainAsset)

        let presenter = TopUpRequestPresenter(
            interactor: interactor,
            wireframe: wireframe,
            productId: context.productId,
            amount: context.amount,
            chainAsset: chainAsset,
            viewModelFactory: viewModelFactory
        )

        let view = TopUpRequestViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        BottomSheetViewFacade.setupNonNavigatingSheet(from: view, preferredHeight: nil)

        return view
    }
}
