import Foundation
import PolkadotUI
import Products

struct SPATabChipViewModel {
    let id: UUID
    let name: String
    let icon: ImageViewModelProtocol?
}

@MainActor
final class SPATabChipViewModelFactory {
    private let dotNsResolverProvider: () -> DotNsResolverProtocol?
    private let htmlParser: ProductLinkHTMLParsing

    private var cachedResolver: DotNsResolverProtocol?

    init(
        dotNsResolver: @escaping () -> DotNsResolverProtocol?,
        htmlParser: ProductLinkHTMLParsing = ProductLinkHTMLParser()
    ) {
        dotNsResolverProvider = dotNsResolver
        self.htmlParser = htmlParser
    }

    func createViewModels(for tabs: [SPATab]) -> [SPATabChipViewModel] {
        tabs.map { tab in
            SPATabChipViewModel(id: tab.id, name: name(for: tab), icon: icon(for: tab))
        }
    }
}

private extension SPATabChipViewModelFactory {
    func resolver() -> DotNsResolverProtocol? {
        if let cachedResolver {
            return cachedResolver
        }

        cachedResolver = dotNsResolverProvider()

        return cachedResolver
    }

    func name(for tab: SPATab) -> String {
        ProductHost(rawString: tab.dotDomain)?.name
            ?? String(localized: .Products.productTabsNotAvailable)
    }

    func icon(for tab: SPATab) -> ImageViewModelProtocol? {
        guard let resolver = resolver() else {
            return nil
        }

        return ProductLinkIconImageViewModel(
            provider: ProductLinkIconImageDataProvider(
                domain: tab.dotDomain,
                dotNsResolver: resolver,
                htmlParser: htmlParser
            )
        )
    }
}
