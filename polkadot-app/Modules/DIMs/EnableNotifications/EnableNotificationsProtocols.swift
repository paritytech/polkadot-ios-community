import PolkadotUI
import UIKitExt

protocol EnableNotificationsViewProtocol: ControllerBackedProtocol {
    func didReceive(reasonsViewModel: EnableNotificationsViewLayout.ViewModel)
}

protocol EnableNotificationsPresenterProtocol: AnyObject {
    func setup()
    func enableNotifications()
    func discardNotifications()
}

protocol EnableNotificationsInteractorInputProtocol: AnyObject {
    func setup()
    func requestNotificationsAccess()
    func confirmDiscardNotifications()
}

protocol EnableNotificationsInteractorOutputProtocol: AnyObject {
    func didReceive(status: NotificationAccessStatus)
    func didReceive(accessGranted: Bool)
    func didReceiveGoToSettings()
}

protocol EnableNotificationsWireframeProtocol: AnyObject, ApplicationSettingsPresentable {
    func confirmDiscard(
        on view: EnableNotificationsViewProtocol?,
        with model: DiscardNotificationsModel,
        viewModelFactory: DiscardNotificationsViewModelMaking
    )
}
