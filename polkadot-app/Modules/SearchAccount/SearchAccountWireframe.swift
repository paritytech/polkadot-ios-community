import UIKit
import Coinage

final class SearchAccountWireframe: SearchAccountWireframeProtocol {
    let coinageServicing: CoinageServicing
    init(coinageServicing: CoinageServicing) {
        self.coinageServicing = coinageServicing
    }

    func showTransfer(
        from view: SearchAccountViewProtocol?,
        recipient: RecipientModel,
        chainAsset: ChainAsset
    ) {
        guard
            let destination = TransferAmountViewFactory.createTransfer(
                for: chainAsset,
                recipient: recipient,
                coinageService: coinageServicing
            )
        else {
            return
        }

        view?.controller.navigationController?.pushViewController(destination.controller, animated: true)
    }
}
