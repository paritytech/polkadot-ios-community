import Foundation
import PolkadotUI
import Products

extension ChatViewModelFactory {
    /// Detects the first product universal link in the message text
    /// Returns empty text if text is equal to url
    func resolveProductLinkPreview(
        text: String,
        status: Chat.LocalMessage.Status,
        actions: ChatViewModelActions?
    ) -> (text: String, preview: ChatProductLinkPreviewConfiguration?) {
        guard let detected = ProductURLDetector.firstProductLink(in: text) else {
            return (text, nil)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedText: String = trimmed == detected.matchedURL ? "" : text

        let htmlParser = ProductLinkHTMLParser()

        let nameProvider = ProductNameProvider(
            host: detected.host,
            productRepository: productRepository,
            dotNsResolver: dotNsResolver,
            nameCache: productNameCache,
            htmlParser: htmlParser
        )

        let imageViewModel: ImageViewModelProtocol? = dotNsResolver.map { resolver in
            ProductLinkIconImageViewModel(
                provider: ProductLinkIconImageDataProvider(
                    domain: detected.host.toDotDomain(),
                    dotNsResolver: resolver,
                    htmlParser: htmlParser
                )
            )
        }

        let preview = ChatProductLinkPreviewConfiguration(
            domain: detected.host.toDotDomain(),
            style: previewStyle(for: status),
            nameProvider: nameProvider,
            imageViewModel: imageViewModel,
            tap: {
                guard
                    let url = URL(string: detected.matchedURL),
                    let productPage = ProductPage.fromUrl(url)
                else { return }

                actions?.openProduct(productPage)
            }
        )

        return (strippedText, preview)
    }

    private func previewStyle(
        for status: Chat.LocalMessage.Status
    ) -> ChatProductLinkPreviewConfiguration.Style {
        switch status {
        case .incoming: .inbox
        case .outgoing: .outbox
        }
    }
}
