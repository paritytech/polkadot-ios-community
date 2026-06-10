import PolkadotUI
import UIKitExt

protocol PolkadotSigningDetailsViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: PolkadotSigningDetailsViewLayout.ViewModel)
}

protocol PolkadotSigningDetailsPresenterProtocol: AnyObject {
    func setup()
}

protocol PolkadotSigningDetailsWireframeProtocol: AnyObject {
    func hide(view: PolkadotSigningDetailsViewProtocol?)
}
