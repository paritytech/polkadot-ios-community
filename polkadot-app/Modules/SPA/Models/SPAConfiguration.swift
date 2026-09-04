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
    /// Set by the truapi E2E launcher; drives the simulator straight to the
    /// product under test instead of the wallet tab.
    static var isSimulatorBrowseRequested: Bool {
        #if IOS_PASEO_E2E && targetEnvironment(simulator)
            ProcessInfo.processInfo.environment["TRUAPI_IOS_E2E_BROWSE"] == "1"
        #else
            false
        #endif
    }

    static func browseRoot(host: ProductHost) -> SPAConfiguration {
        #if IOS_PASEO_E2E && targetEnvironment(simulator)
            // The truapi E2E launcher serves the product from a loopback URL
            // instead of dotNS.
            let e2eSource = ProcessInfo.processInfo.environment["TRUAPI_IOS_E2E_PRODUCT_URL"]
                .flatMap(URL.init(string:))
            if let source = e2eSource {
                return SPAConfiguration(
                    title: nil,
                    isRootScreen: true,
                    showMoreButton: false,
                    page: ProductPage(host: host),
                    contentSource: .directURL(source)
                )
            }
        #endif

        return SPAConfiguration(
            title: nil,
            isRootScreen: true,
            showMoreButton: false,
            page: ProductPage(host: host)
        )
    }
}
