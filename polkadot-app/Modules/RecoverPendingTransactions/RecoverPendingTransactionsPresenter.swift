import Foundation
import PolkadotUI
import BigInt
import SubstrateSdk
import UIKitExt

@MainActor
final class RecoverPendingTransactionsPresenter {
    weak var view: (any RecoverPendingTransactionsViewProtocol)?
    let wireframe: RecoverPendingTransactionsWireframeProtocol
    let interactor: RecoverPendingTransactionsInteractorInputProtocol

    private let amountFactory: TransferAmountViewModelFactoryProtocol

    init(
        interactor: RecoverPendingTransactionsInteractorInputProtocol,
        wireframe: RecoverPendingTransactionsWireframeProtocol,
        amountFactory: TransferAmountViewModelFactoryProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.amountFactory = amountFactory
    }
}

extension RecoverPendingTransactionsPresenter: RecoverPendingTransactionsPresenterProtocol {
    func setup() {
        interactor.setup()
        view?.applyState(.idle)
    }

    func didTapRecover() {
        interactor.recover()
    }
}

extension RecoverPendingTransactionsPresenter: RecoverPendingTransactionsInteractorOutputProtocol {
    func didUpdateState(_ state: SpentCoinsRecoveryState) {
        view?.applyState(viewState(for: state))
    }
}

private extension RecoverPendingTransactionsPresenter {
    func viewState(for state: SpentCoinsRecoveryState) -> RecoverPendingTransactionsViewState {
        switch state {
        case .idle:
            .idle
        case .inProgress:
            RecoverPendingTransactionsViewState(
                isLoading: true,
                bannerText: nil,
                bannerStyle: .success
            )
        case let .completed(amount):
            RecoverPendingTransactionsViewState(
                isLoading: false,
                bannerText: completedBannerText(for: amount),
                bannerStyle: .success
            )
        case let .failed(message):
            RecoverPendingTransactionsViewState(
                isLoading: false,
                bannerText: String(localized: .recoverPendingTransactionsBannerError(message)),
                bannerStyle: .error
            )
        }
    }

    func completedBannerText(for amount: Balance) -> String {
        guard amount > .zero else {
            return String(localized: .recoverPendingTransactionsBannerEmpty)
        }
        let formatted = amountFactory.amount(from: amount)
        return String(localized: .recoverPendingTransactionsBannerSuccess(formatted))
    }
}
