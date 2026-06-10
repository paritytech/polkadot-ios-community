import Foundation
import SubstrateSdk

enum ConfirmDepositViewFactory {
    static func createView(
        asset: ChainAssetId,
        amount: Balance,
        model: ConfirmDepositModel
    ) -> ConfirmDepositViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        guard
            let chain = chainRegistry.getChain(for: asset.chainId),
            let asset = chain.chainAsset(for: asset.assetId)
        else {
            return nil
        }
        let interactor = ConfirmDepositInteractor(
            candidateWallet: SelectedWallet.candidate,
            chainAsset: asset,
            logger: Logger.shared
        )
        let viewModelFactory = ConfirmDepositViewModelFactory(chainAsset: asset)

        let presenter = ConfirmDepositPresenter(
            interactor: interactor,
            amount: amount,
            chainAsset: asset,
            model: model,
            viewModelFactory: viewModelFactory
        )

        let view = ConfirmDepositViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        BottomSheetViewFacade.setupBottomSheet(from: view.controller, preferredHeight: nil)

        return view
    }
}
