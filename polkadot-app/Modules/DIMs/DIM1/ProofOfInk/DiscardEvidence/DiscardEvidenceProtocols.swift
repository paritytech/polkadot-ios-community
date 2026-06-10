import UIKitExt

protocol DiscardEvidenceViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: DiscardEvidenceViewModel)
}

protocol DiscardEvidencePresenterProtocol: AnyObject {
    func setup()
    func cancel()
    func discard()
}

protocol DiscardEvidenceWireframeProtocol: AnyObject {
    func close(view: DiscardEvidenceViewProtocol?, _ completion: (() -> Void)?)
}
