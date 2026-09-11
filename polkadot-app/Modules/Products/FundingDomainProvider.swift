import Foundation
import Products

/// Resolves the funding product's entry pages from remote config: one URL for topping up, one for
/// withdrawing. Both are full product URLs (host with TLD, optional path), so a product can serve
/// each flow from a different page.
protocol FundingDomainProviding: Sendable {
    func fundingPage() async throws -> ProductPage
    func offrampPage() async throws -> ProductPage
}

enum FundingDomainError: Error {
    case unavailable
}

final class FundingDomainProvider: FundingDomainProviding, @unchecked Sendable {
    private let hostProvider: ProductHostProviding
    private let remoteConfig: @Sendable () -> RemoteAppConfig?

    init(
        hostProvider: ProductHostProviding,
        remoteConfig: @escaping @Sendable () -> RemoteAppConfig? = { AppConfigProvider.shared.getRemoteConfig() }
    ) {
        self.hostProvider = hostProvider
        self.remoteConfig = remoteConfig
    }

    func fundingPage() async throws -> ProductPage {
        try await page(for: remoteConfig()?.fundingUrl)
    }

    func offrampPage() async throws -> ProductPage {
        try await page(for: remoteConfig()?.offrampUrl)
    }
}

private extension FundingDomainProvider {
    /// Awaits the chain TLD through the host provider, then parses the URL into a page.
    func page(for url: URL?) async throws -> ProductPage {
        guard let url, let host = url.host() else {
            throw FundingDomainError.unavailable
        }

        guard try await hostProvider.resolveHost(rawString: host) != nil,
              let page = hostProvider.page(url: url)
        else {
            throw FundingDomainError.unavailable
        }

        return page
    }
}
