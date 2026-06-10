import UIKitExt

protocol TransactionSuccessViewProtocol: ControllerBackedProtocol {}

protocol TransactionSuccessPresenterProtocol: AnyObject {
    func setup()
    func onAppear()
    func activateDone()
}

protocol TransactionSuccessWireframeProtocol: AnyObject {
    func hide(view: TransactionSuccessViewProtocol?)
}

typealias TransactionSuccessCompletion = () -> Void
