import PolkadotUI
import UIKitExt

protocol TopUpRequestViewProtocol: ControllerBackedProtocol {
    func didReceive(title: String, amount: String, claimButtonTitle: String)
    func didReceive(isClaiming: Bool)
    func didReceive(warningMessage: String?)
}

protocol TopUpRequestPresenterProtocol: AnyObject {
    func setup()
    func didTapClaim()
}

protocol TopUpRequestInteractorInputProtocol: AnyObject {
    func setup()
    func claim()
}

@MainActor
protocol TopUpRequestInteractorOutputProtocol: AnyObject {
    func didStartClaim()
    func didFinishClaim()
    func didFailClaim(_ error: Error)
    func didDetectAmountMismatch()
    func didFailDetection()
}

@MainActor
protocol TopUpRequestWireframeProtocol: AnyObject {
    func dismiss(view: TopUpRequestViewProtocol?)
}
