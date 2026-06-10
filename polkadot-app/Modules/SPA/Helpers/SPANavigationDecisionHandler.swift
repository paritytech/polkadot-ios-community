import WebKit
import Products

enum SPANavigationDecision {
    case allow
    case intercept(URL)
}

protocol SPANavigationDecisionHandling {
    func decide(for navigationAction: WKNavigationAction) -> SPANavigationDecision
}

final class DotNsNavigationDecisionHandler: SPANavigationDecisionHandling {
    private let baseHost: ProductHost

    init(baseHost: ProductHost) {
        self.baseHost = baseHost
    }

    func decide(for navigationAction: WKNavigationAction) -> SPANavigationDecision {
        guard let url = navigationAction.request.url,
              let host = ProductHost.fromUrl(url)
        else {
            return .allow
        }

        if host.toDotDomain() != baseHost.toDotDomain() {
            return .intercept(url)
        }

        return .allow
    }
}
