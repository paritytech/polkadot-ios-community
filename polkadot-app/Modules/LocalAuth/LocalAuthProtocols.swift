import UIKitExt

protocol LocalAuthViewProtocol: ControllerBackedProtocol {
    func didStartAuth()
    func didStopAuth()
}

protocol LocalAuthPresenterProtocol: AnyObject {
    func setup()
    func retryAuth()
}

protocol LocalAuthInteractorInputProtocol: AnyObject {
    func startAuth(with reason: String)
}

protocol LocalAuthInteractorOutputProtocol: AnyObject {
    func didCompleteAuth()
    func didInterruptAuth()
    func didFailedAuth(with error: DeviceAuthError)
}

protocol LocalAuthWireframeProtocol: AnyObject {
    func complete(with isSuccess: Bool)
    func showAuthFailed(from view: LocalAuthViewProtocol?, completion: @escaping () -> Void)
}
