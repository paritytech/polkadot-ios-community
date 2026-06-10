import UIKitExt

protocol TransferPrivacyViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: TransferPrivacyViewModel)
}

protocol TransferPrivacyPresenterProtocol: AnyObject {
    func setup()
    func activateLink()
    func selectMain()
    func selectSecondary()
    func cancel()
}

protocol TransferPrivacyWireframeProtocol: AnyObject {
    func showInfo(from view: TransferPrivacyViewProtocol?)
    func complete(from view: TransferPrivacyViewProtocol?, _ completion: (() -> Void)?)
    func close(from view: TransferPrivacyViewProtocol?)
}
