import Foundation
import Products

enum SPAContentSource {
    /// Resolve the dotNs product and serve it via the polkadot:// scheme handler.
    case dotNs
    /// Debug: load the URL as-is, skipping resolution. Serves a product from a development server —
    /// see ``LocalDevOrigin``. Honoured by both the rust and the native runtime.
    case directURL(URL)
}

struct SPAConfiguration {
    let title: String?
    let isRootScreen: Bool
    let showMoreButton: Bool
    let page: ProductPage
    let contentSource: SPAContentSource
    let isBrowserTab: Bool
    let browserTabId: UUID?

    init(
        title: String?,
        isRootScreen: Bool,
        showMoreButton: Bool,
        page: ProductPage,
        contentSource: SPAContentSource = .dotNs,
        isBrowserTab: Bool = false,
        browserTabId: UUID? = nil
    ) {
        self.title = title
        self.isRootScreen = isRootScreen
        self.showMoreButton = showMoreButton
        self.page = page
        self.contentSource = contentSource
        self.isBrowserTab = isBrowserTab
        self.browserTabId = browserTabId
    }
}

extension SPAConfiguration {
    /// Identity the product transacts under — what permissions, storage and account derivation key off.
    ///
    /// A dotNS product is its dot domain. A product served from a development server is the origin it
    /// is served from, which is also the string `window.location.host` hands the page: products send
    /// their own identifier back to the host, so the two have to agree.
    var productId: ProductId {
        switch contentSource {
        case .dotNs:
            return page.host.toDotDomain()

        case let .directURL(url):
            guard let host = url.host else { return page.host.toDotDomain() }

            return url.port.map { "\(host):\($0)" } ?? host
        }
    }

    static func browseRoot(host: ProductHost) -> SPAConfiguration {
        SPAConfiguration(
            title: nil,
            isRootScreen: true,
            showMoreButton: false,
            page: ProductPage(host: host)
        )
    }
}
