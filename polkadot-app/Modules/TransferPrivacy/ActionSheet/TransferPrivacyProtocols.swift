import UIKitExt

protocol TransferPrivacyViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: TransferPrivacyViewModel)
}

@MainActor
protocol TransferPrivacyPresenterProtocol: AnyObject {
    func setup()
    func sendAnyway()
    func cancel()
    /// Backdrop tap or swipe: the sheet is already gone, only the decision is outstanding.
    func dismissedExternally()
}

@MainActor
protocol TransferPrivacyWireframeProtocol: AnyObject {
    func complete(from view: TransferPrivacyViewProtocol?, _ completion: (() -> Void)?)
}
