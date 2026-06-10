import Foundation

protocol DeferredLinkHandling {
    func handle(with url: URL)
    func register(_ handler: URLHandlingServiceProtocol)
}

final class DeferredLinkHandler {
    static let shared = DeferredLinkHandler()

    private weak var handler: URLHandlingServiceProtocol?
    private var deeplinkURL: URL?
}

extension DeferredLinkHandler: DeferredLinkHandling {
    func handle(with url: URL) {
        deeplinkURL = url
        handlePendingUrl()
    }

    func register(_ handler: URLHandlingServiceProtocol) {
        guard self.handler !== handler else {
            return
        }
        self.handler = handler
        handlePendingUrl()
    }
}

private extension DeferredLinkHandler {
    func handlePendingUrl() {
        guard let handler, let deeplinkURL else {
            return
        }
        _ = handler.handle(url: deeplinkURL)
        self.deeplinkURL = nil
    }
}
