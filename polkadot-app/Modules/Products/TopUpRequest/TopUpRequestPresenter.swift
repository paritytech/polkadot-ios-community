import Foundation
import PolkadotUI
import Products
import SubstrateSdk

final class TopUpRequestPresenter {
    weak var view: TopUpRequestViewProtocol?
    let wireframe: TopUpRequestWireframeProtocol
    let interactor: TopUpRequestInteractorInputProtocol

    private let productId: ProductId
    private let amount: Balance
    private let chainAsset: ChainAsset
    private let viewModelFactory: TopUpRequestViewModelMaking

    init(
        interactor: TopUpRequestInteractorInputProtocol,
        wireframe: TopUpRequestWireframeProtocol,
        productId: ProductId,
        amount: Balance,
        chainAsset: ChainAsset,
        viewModelFactory: TopUpRequestViewModelMaking
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.productId = productId
        self.amount = amount
        self.chainAsset = chainAsset
        self.viewModelFactory = viewModelFactory
    }
}

extension TopUpRequestPresenter: TopUpRequestPresenterProtocol {
    func setup() {
        view?.didReceive(
            title: viewModelFactory.formatTitle(productId: productId),
            amount: viewModelFactory.formatAmount(amount),
            claimButtonTitle: viewModelFactory.claimButtonTitle()
        )
        view?.didReceive(warningMessage: nil)
        interactor.setup()
    }

    func didTapClaim() {
        interactor.claim()
    }
}

extension TopUpRequestPresenter: TopUpRequestInteractorOutputProtocol {
    func didStartClaim() {
        view?.didReceive(isClaiming: true)
    }

    func didFinishClaim() {
        view?.didReceive(isClaiming: false)
        wireframe.dismiss(view: view)
    }

    func didFailClaim(_: Error) {
        view?.didReceive(isClaiming: false)
        wireframe.dismiss(view: view)
    }

    func didDetectAmountMismatch() {
        view?.didReceive(warningMessage: viewModelFactory.amountMismatchWarning())
    }

    func didFailDetection() {
        view?.didReceive(warningMessage: viewModelFactory.amountDetectionFailedWarning())
    }
}
