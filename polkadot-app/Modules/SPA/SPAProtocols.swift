import Foundation
import Products
import UIKitExt

protocol SPAViewProtocol: ControllerBackedProtocol {
    func navigate(to url: URL)
    func updateTitle(_ title: String)
    func reload()
    func showLoading()
    func hideLoading()
}

@MainActor
protocol SPAPresenterProtocol: AnyObject {
    func setup(engine: JSEngineProtocol)
    func didTapMoreButton()
    func didInterceptNavigation(to url: URL)
    func didUpdateWebViewTitle(_ title: String)
}

protocol SPAInteractorInputProtocol: AnyObject {
    func setup(engine: JSEngineProtocol)
    func retry()
    func hasChatEntry() -> Bool
    func openChat()
}

@MainActor
protocol SPAInteractorOutputProtocol: AnyObject {
    func didFail(error: Error)
    func didRequestNavigation(to url: URL)
    func didPrepareChat(chatId: Chat.Id)
}

@MainActor
protocol SPAWireframeProtocol: AlertPresentable, ErrorPresentable, CommonRetryable {
    func showProductSPA(from view: ControllerBackedProtocol?, productHost: ProductHost)
    func showMoreActions(
        from view: ControllerBackedProtocol?,
        actions: [SPAMoreAction],
        closeTitle: String
    )
    func shareURL(_ url: URL, from view: ControllerBackedProtocol?)

    func openChat(
        from view: ControllerBackedProtocol?,
        chatId: Chat.Id
    )
}
