import UIKitExt

protocol RestoreFromCloudViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: RestoreFromCloudViewLayout.ViewModel)
}

protocol RestoreFromCloudPresenterProtocol: AnyObject {
    func setup()
    func viewDidAppear()
}

protocol RestoreFromCloudInteractorInputProtocol: AnyObject {
    func restoreWallets()
}

protocol RestoreFromCloudInteractorOutputProtocol: AnyObject {
    func didReceiveInProgress(_ value: Bool)
    func didRestoreWallets()
    func didDecideBroken()
    func authorizeUser(completion: @escaping AuthorizationCompletionBlock)
}

protocol RestoreFromCloudWireframeProtocol: AuthorizationPresentable {
    var observer: RootStateObserving { get }
}
