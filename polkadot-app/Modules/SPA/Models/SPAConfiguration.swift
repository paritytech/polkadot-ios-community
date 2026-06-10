import Foundation
import Products

struct SPAConfiguration {
    let title: String?
    let isRootScreen: Bool
    let showMoreButton: Bool
    let page: ProductPage
}

extension SPAConfiguration {
    static func browseRoot() -> SPAConfiguration {
        SPAConfiguration(
            title: nil,
            isRootScreen: true,
            showMoreButton: false,
            page: ProductPage(host: ProductHost(rawString: AppConfig.DotNs.dotNsBrowse)!)
        )
    }

    static func product(host: ProductHost) -> SPAConfiguration {
        SPAConfiguration(
            title: nil,
            isRootScreen: false,
            showMoreButton: true,
            page: ProductPage(host: host)
        )
    }
}
