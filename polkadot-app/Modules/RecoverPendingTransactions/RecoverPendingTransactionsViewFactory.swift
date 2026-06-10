import Foundation
import Operation_iOS
import Keystore_iOS
import SDKLogger
import SubstrateSdk

enum RecoverPendingTransactionsViewFactory {
    @MainActor
    static func createView(
        serviceCoordinator: ServiceCoordinatorProtocol
    ) -> RecoverPendingTransactionsViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let chainAssetId = AppConfig.Assets.mainAsset

        guard
            let chain = chainRegistry.getChain(for: chainAssetId.chainId),
            let chainAsset = chain.chainAsset(for: chainAssetId.assetId)
        else {
            return nil
        }

        let interactor = RecoverPendingTransactionsInteractor(
            spentCoinsRecoveryService: serviceCoordinator.spentCoinsRecoveryService
        )

        let wireframe = RecoverPendingTransactionsWireframe()

        let amountFactory = TransferAmountViewModelFactory(
            targetAssetInfo: chainAsset.asset.digitalDollarDisplayInfo,
            formatterFactory: AssetBalanceFormatterFactory()
        )

        let presenter = RecoverPendingTransactionsPresenter(
            interactor: interactor,
            wireframe: wireframe,
            amountFactory: amountFactory
        )

        let view = RecoverPendingTransactionsViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
