import Foundation
import Products

protocol MerchantDomainProviding: Sendable {
    func merchantPage() async throws -> ProductPage
}

enum MerchantDomainError: Error {
    case unavailable
}

final class MerchantDomainProvider: MerchantDomainProviding, @unchecked Sendable {
    private let hostProvider: @Sendable () -> ProductHostProviding
    private let destination: @Sendable () -> String?
    private let defaultLabel: String

    init(
        hostProvider: @escaping @Sendable () -> ProductHostProviding,
        destination: @escaping @Sendable () -> String? = { AppConfig.DotNs.merchantDestination },
        defaultLabel: String = AppConfig.DotNs.dotNsMerchantDefault
    ) {
        self.hostProvider = hostProvider
        self.destination = destination
        self.defaultLabel = defaultLabel
    }

    func merchantPage() async throws -> ProductPage {
        let provider = hostProvider()

        guard let destination = destination(), !destination.isEmpty else {
            return try await page(label: defaultLabel, provider: provider)
        }

        let host = URL(string: destination)?.host() ?? destination

        guard ProductHost.name(fromDotDomain: host) != nil else {
            return try await page(label: host, provider: provider)
        }

        guard try await provider.resolveHost(rawString: host) != nil,
              let page = provider.page(navigationDestination: destination)
        else {
            throw MerchantDomainError.unavailable
        }

        return page
    }
}

// MARK: - Private functions

extension MerchantDomainProvider {
    private func page(label: String, provider: ProductHostProviding) async throws -> ProductPage {
        guard let host = try await provider.resolveHost(label: label) else {
            throw MerchantDomainError.unavailable
        }

        return ProductPage(host: host)
    }
}
