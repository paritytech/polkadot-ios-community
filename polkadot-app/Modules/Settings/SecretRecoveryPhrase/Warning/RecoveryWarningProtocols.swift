import Combine
import UIKitExt

protocol RecoveryWarningViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModels: [RecoveryWarningViewLayout.Model])
}

protocol RecoveryWarningPresenterProtocol: AnyObject {
    func setup()
    func onClose()
    func onAction()
}

protocol RecoveryWarningInteractorInputProtocol: AnyObject {}

protocol RecoveryWarningInteractorOutputProtocol: AnyObject {}

protocol RecoveryWarningWireframeProtocol: AnyObject, AlertPresentable, CommonRetryable {
    func hide(view: RecoveryWarningViewProtocol?)
    func hideWithAction(view: RecoveryWarningViewProtocol?)
}
