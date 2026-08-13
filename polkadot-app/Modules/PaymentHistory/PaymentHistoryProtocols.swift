import PolkadotUI
import UIKitExt

protocol PaymentHistoryViewProtocol: ControllerBackedProtocol {
    func applyItems(_ items: [PaymentHistoryViewModel.Item])
}

@MainActor
protocol PaymentHistoryPresenterProtocol: AnyObject {
    func setup()
}

protocol PaymentHistoryInteractorInputProtocol: AnyObject {
    func setup()
}

@MainActor
protocol PaymentHistoryInteractorOutputProtocol: AnyObject {
    func didReceive(records: [W3sPaymentRecord])
}

@MainActor
protocol PaymentHistoryWireframeProtocol: AnyObject, AlertPresentable {}
