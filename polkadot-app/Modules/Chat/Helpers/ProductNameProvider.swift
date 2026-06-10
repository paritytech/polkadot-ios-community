import Foundation
import Operation_iOS
import PolkadotUI
import Products

actor ProductNameProvider {
    private nonisolated let host: ProductHost
    private nonisolated let productRepository: AnyDataProviderRepository<Product>
    private nonisolated let dotNsResolver: DotNsResolverProtocol?
    private nonisolated let nameCache: ProductNameCaching
    private nonisolated let htmlParser: ProductLinkHTMLParsing
    private var currentTask: Task<Void, Never>?

    init(
        host: ProductHost,
        productRepository: AnyDataProviderRepository<Product>,
        dotNsResolver: DotNsResolverProtocol?,
        nameCache: ProductNameCaching,
        htmlParser: ProductLinkHTMLParsing = ProductLinkHTMLParser()
    ) {
        self.host = host
        self.productRepository = productRepository
        self.dotNsResolver = dotNsResolver
        self.nameCache = nameCache
        self.htmlParser = htmlParser
    }
}

extension ProductNameProvider: ChatProductNameProviding {
    nonisolated var identifier: String { host.toDotDomain() }

    nonisolated func provideName(
        _ completion: @escaping (String?) -> Void
    ) {
        Task { [weak self] in
            await self?.handleProvide(completion)
        }
    }

    nonisolated func cancel() {
        Task { [weak self] in
            await self?.handleCancel()
        }
    }
}

private extension ProductNameProvider {
    func handleProvide(
        _ completion: @escaping (String?) -> Void
    ) {
        currentTask?.cancel()

        currentTask = Task { [weak self] in
            guard let self else { return }

            let resolvedName = await resolveName()

            await MainActor.run {
                completion(resolvedName)
            }
        }
    }

    func handleCancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    nonisolated func resolveName() async -> String {
        let domain = host.toDotDomain()
        let fallback = host.name

        if let cachedName = nameCache.name(for: domain) {
            return cachedName
        }

        let storedProduct = try? await productRepository
            .fetchOperation(by: { domain }, options: RepositoryFetchOptions())
            .asyncExecute()

        let resolved: String =
            if let storedName = storedProduct?.name, storedName != fallback {
                storedName
            } else if let title = await fetchHTMLTitle(domain: domain) {
                title
            } else {
                storedProduct?.name ?? fallback
            }

        if resolved != fallback, !Task.isCancelled {
            nameCache.store(name: resolved, for: domain)
        }

        return resolved
    }

    nonisolated func fetchHTMLTitle(domain: String) async -> String? {
        guard
            let dotNsResolver,
            let contentDirectory = try? await dotNsResolver.resolveToLocalURL(dotNsName: domain)
        else {
            return nil
        }
        let indexURL = contentDirectory.appendingPathComponent(ProductBundle.indexHTML)
        guard let html = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return nil
        }
        return htmlParser.title(in: html)
    }
}
