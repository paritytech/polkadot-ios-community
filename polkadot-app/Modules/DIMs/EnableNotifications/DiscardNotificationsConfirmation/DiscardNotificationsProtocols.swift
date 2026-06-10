import UIKitExt

protocol DiscardNotificationsViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: DiscardNotificationsViewLayout.ViewModel)
}

protocol DiscardNotificationsPresenterProtocol: AnyObject {
    func setup()
    func enableNotifications()
    func discardNotifications()
}

protocol DiscardNotificationsWireframeProtocol: AnyObject {
    func close(view: DiscardNotificationsViewProtocol?, completion: (() -> Void)?)
}
