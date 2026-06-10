import UIKitExt

protocol EvidenceTipsViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: EvidenceTipsViewModel)
}

protocol EvidenceTipsPresenterProtocol: AnyObject {
    func setup()
}

protocol EvidenceTipsWireframeProtocol: AnyObject {}
