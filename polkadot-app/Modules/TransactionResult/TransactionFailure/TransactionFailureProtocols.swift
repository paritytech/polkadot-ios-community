import UIKitExt

protocol TransactionFailureViewProtocol: ControllerBackedProtocol, AlertPresentable {}

protocol TransactionFailurePresenterProtocol: AnyObject {
    func setup()
    func onAppear()
    func onAction()
}

protocol TransactionFailureWireframeProtocol: AnyObject {
    func hide(view: TransactionFailureViewProtocol?)
}

typealias TransactionFailureCompletion = () -> Void
