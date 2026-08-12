import Foundation
import Kingfisher
@preconcurrency import Products
import PolkadotUI
import SwiftUI

enum ProductLinkIconImageDataProviderError: Error {
    case iconLinkNotFound
}

final class ProductLinkIconImageDataProvider {
    let cacheKey: String

    private let domain: String
    private let dotNsResolver: DotNsResolverProtocol
    private let htmlParser: ProductLinkHTMLParsing
    private let logger: LoggerProtocol

    init(
        domain: String,
        dotNsResolver: DotNsResolverProtocol,
        htmlParser: ProductLinkHTMLParsing,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.domain = domain
        self.dotNsResolver = dotNsResolver
        self.htmlParser = htmlParser
        self.logger = logger
        cacheKey = "ProductLinkIcon-\(domain)"
    }
}

extension ProductLinkIconImageDataProvider: ImageDataProvider, @unchecked Sendable {
    func data(handler: @escaping (Result<Data, Error>) -> Void) {
        Task(priority: .medium) {
            do {
                let data = try await loadIconData()
                handler(.success(data))
            } catch ProductLinkIconImageDataProviderError.iconLinkNotFound {
                if let fallback = await makeLetterIconData() {
                    handler(.success(fallback))
                } else {
                    handler(.failure(ProductLinkIconImageDataProviderError.iconLinkNotFound))
                }
            } catch {
                logger.error("Failed to load product icon for \(domain): \(error)")
                handler(.failure(error))
            }
        }
    }
}

private extension ProductLinkIconImageDataProvider {
    func loadIconData() async throws -> Data {
        let contentDirectory = try await dotNsResolver.resolveToLocalURL(dotNsName: domain)
        let html = try String(
            contentsOf: contentDirectory.appendingPathComponent(ProductBundle.indexHTML),
            encoding: .utf8
        )
        guard let raw = htmlParser.iconRelativePath(in: html) else {
            throw ProductLinkIconImageDataProviderError.iconLinkNotFound
        }
        let iconURL = contentDirectory.appendingPathComponent(raw)
        return try Data(contentsOf: iconURL)
    }

    @MainActor
    func makeLetterIconData() -> Data? {
        let viewModel = AvatarViewModel.colored(
            text: String(domain.prefix(1)),
            colorSeed: domain
        )

        let renderer = ImageRenderer(content: DSAvatar(viewModel: viewModel, size: .s64))
        renderer.scale = UIScreen.main.scale

        return renderer.uiImage?.pngData()
    }
}
