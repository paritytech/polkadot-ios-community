import WebKit
import Products

enum SPANavigationDecision: Equatable {
    case allow
    case intercept(URL)
}

protocol SPANavigationDecisionHandling {
    func decide(for navigationAction: WKNavigationAction) -> SPANavigationDecision
}

/// Debug direct-URL mode: allow same-host navigation, intercept everything else.
final class DirectURLNavigationDecisionHandler: SPANavigationDecisionHandling {
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func decide(for navigationAction: WKNavigationAction) -> SPANavigationDecision {
        guard let url = navigationAction.request.url else { return .allow }
        return decide(url: url)
    }

    func decide(url: URL) -> SPANavigationDecision {
        if url.host == baseURL.host, url.port == baseURL.port {
            return .allow
        }
        return .intercept(url)
    }
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
