import PolkadotUI
import BigInt
import UIKitExt

struct RecoverPendingTransactionsViewState {
    let isLoading: Bool
    let bannerText: String?
    let bannerStyle: RecoverPendingTransactionsViewModel.BannerStyle

    static let idle = RecoverPendingTransactionsViewState(
        isLoading: false,
        bannerText: nil,
        bannerStyle: .success
    )
}

protocol RecoverPendingTransactionsViewProtocol: ControllerBackedProtocol {
    func applyState(_ viewState: RecoverPendingTransactionsViewState)
}

@MainActor
protocol RecoverPendingTransactionsPresenterProtocol: AnyObject {
    func setup()
    func didTapRecover()
}

protocol RecoverPendingTransactionsInteractorInputProtocol: AnyObject {
    func setup()
    func recover()
}

@MainActor
protocol RecoverPendingTransactionsInteractorOutputProtocol: AnyObject {
    func didUpdateState(_ state: SpentCoinsRecoveryState)
}

@MainActor
protocol RecoverPendingTransactionsWireframeProtocol: AnyObject {}
