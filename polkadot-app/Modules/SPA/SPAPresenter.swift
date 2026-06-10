import Foundation
import Products
import UIKit

final class SPAPresenter {
    weak var view: SPAViewProtocol?
    let interactor: SPAInteractorInputProtocol
    let wireframe: SPAWireframeProtocol
    let configuration: SPAConfiguration

    init(
        interactor: SPAInteractorInputProtocol,
        wireframe: SPAWireframeProtocol,
        configuration: SPAConfiguration
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.configuration = configuration
    }
}

extension SPAPresenter: SPAPresenterProtocol {
    func setup(engine: JSEngineProtocol) {
        view?.showLoading()
        interactor.setup(engine: engine)
    }

    func didTapMoreButton() {
        var actions: [SPAMoreAction] = []

        if interactor.hasChatEntry() {
            actions.append(
                SPAMoreAction(
                    icon: .iconChatBubble,
                    title: String(localized: .spaActionOpenChat),
                    isEnabled: true,
                    handler: { [weak self] in self?.interactor.openChat() }
                )
            )
        }

        [
            SPAMoreAction(
                icon: .iconRefresh,
                title: String(localized: .spaActionRefresh),
                isEnabled: true,
                handler: { [weak self] in self?.view?.reload() }
            ),
            SPAMoreAction(
                icon: .iconShare,
                title: String(localized: .spaActionShare),
                isEnabled: true,
                handler: { [weak self] in
                    guard let self else { return }
                    let host = configuration.page.host.name
                    guard let url = AppConfig.ProductUniversalLink.url(for: host) else {
                        return
                    }
                    wireframe.shareURL(url, from: view)
                }
            )
        ].forEach { actions.append($0) }

        wireframe.showMoreActions(
            from: view,
            actions: actions,
            closeTitle: String(localized: .spaActionClose)
        )
    }

    func didInterceptNavigation(to url: URL) {
        guard let productHost = ProductHost.fromUrl(url) else { return }

        wireframe.showProductSPA(from: view, productHost: productHost)
    }

    func didUpdateWebViewTitle(_ title: String) {
        view?.updateTitle(title)
    }
}

extension SPAPresenter: SPAInteractorOutputProtocol {
    func didRequestNavigation(to url: URL) {
        view?.hideLoading()
        view?.navigate(to: url)
    }

    func didPrepareChat(chatId: Chat.Id) {
        wireframe.openChat(from: view, chatId: chatId)
    }

    func didFail(error _: Error) {
        view?.hideLoading()
        wireframe.presentRequestStatus(on: view) { [weak self] in
            self?.view?.showLoading()
            self?.interactor.retry()
        }
    }
}
