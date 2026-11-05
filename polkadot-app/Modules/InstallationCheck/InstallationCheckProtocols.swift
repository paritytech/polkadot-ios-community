import PolkadotUI
import UIKitExt

protocol InstallationCheckViewProtocol: ControllerBackedProtocol {}

protocol InstallationCheckPresenterProtocol: AnyObject {
    func setup()
}

protocol InstallationCheckInteractorInputProtocol: AnyObject {
    func start()
}

@MainActor
protocol InstallationCheckInteractorOutputProtocol: AnyObject {
    func didSettleStatus()
}

@MainActor
protocol InstallationCheckWireframeProtocol: AnyObject {
    func complete()
}
