import UIKitExt

protocol DiscardDIMViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: DiscardDIMViewModel)
    func didReceive(activity active: Bool)
}

protocol DiscardDIMPresenterProtocol: AnyObject {
    func setup()
    func cancel()
    func discardReservation()
}

protocol DiscardDIMWireframeProtocol: AnyObject {
    func close(view: DiscardDIMViewProtocol?, completion: (() -> Void)?)
}
