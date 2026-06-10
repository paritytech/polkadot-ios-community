import PolkadotUI
import UIKitExt

protocol PolkadotSigningViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: PolkadotSigningViewLayout.ViewModel)
}

protocol PolkadotSigningPresenterProtocol: AnyObject {
    func setup()
    func sign()
    func cancel()
    func viewDetails()
}

protocol PolkadotSigningInteractorInputProtocol: AnyObject {
    func setup()
    func signParsedResult(_ parsedResult: PolkadotParsedSigningRequestResult)
    func reject()
}

@MainActor
protocol PolkadotSigningInteractorOutputProtocol: AnyObject {
    func didStartParsingRequest()
    func didFinishParsingRequest(with result: PolkadotParsedSigningRequestResult)
    func didFailToParseRequest(with error: Error)

    func didStartSigning()
    func didFinishSigning()
    func didFailToSign(with error: Error)

    func didStartRejecting()
    func didFinishRejecting()
    func didFailToReject(with error: Error)
}

protocol PolkadotSigningWireframeProtocol: AlertPresentable, ErrorPresentable {
    func hide(view: PolkadotSigningViewProtocol?)
    func showViewDetails(
        with text: String,
        isTransaction: Bool,
        view: PolkadotSigningViewProtocol?
    )
}
