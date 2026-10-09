import Foundation
import Products

enum SPAContentSource {
    /// Resolve the dotNs product and serve it via the polkadot:// scheme handler.
    case dotNs
    /// Debug: load the URL as-is, skipping resolution. Rust runtime only.
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
    /// Whether the screen carries the browser chrome: the floating top pills, chrome collapse and
    /// minimize. A product presented as a modal has none of them.
    let usesBrowserChrome: Bool

    init(
        title: String?,
        isRootScreen: Bool,
        showMoreButton: Bool,
        page: ProductPage,
        contentSource: SPAContentSource = .dotNs,
        isBrowserTab: Bool = false,
        browserTabId: UUID? = nil,
        usesBrowserChrome: Bool = true
    ) {
        self.title = title
        self.isRootScreen = isRootScreen
        self.showMoreButton = showMoreButton
        self.page = page
        self.contentSource = contentSource
        self.isBrowserTab = isBrowserTab
        self.browserTabId = browserTabId
        self.usesBrowserChrome = usesBrowserChrome
    }
}

extension SPAConfiguration {
    static func browseRoot(host: ProductHost) -> SPAConfiguration {
        SPAConfiguration(
            title: nil,
            isRootScreen: true,
            showMoreButton: false,
            page: ProductPage(host: host)
        )
    }
}
