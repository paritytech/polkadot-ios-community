import Foundation
import Products

/// The two funding-product entry points on the CASH card. Both open the funding host; withdraw
/// adds the getcash withdraw sub-path.
enum RampAction: Sendable, Hashable, CaseIterable {
    case topUp
    case withdraw

    enum ResolveError: Error {
        case unresolvedHost
    }

    var subPath: String? {
        switch self {
        case .topUp: nil
        case .withdraw: AppConfig.DotNs.getCashWithdrawPage
        }
    }

    func page(host: ProductHost) -> ProductPage {
        ProductPage(host: host, page: subPath)
    }

    func resolvePage(label: String, using hostProvider: ProductHostProviding) async throws -> ProductPage {
        guard let host = try await hostProvider.resolveHost(label: label) else {
            throw ResolveError.unresolvedHost
        }

        return page(host: host)
    }
}
