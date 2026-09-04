import Foundation
import Products
import SwiftyBeaver

final class BrowseInteractor: BrowseInteractorInputProtocol {
    private let hostProvider: ProductHostProviding
    private let logger: LoggerProtocol
    weak var presenter: BrowseInteractorOutputProtocol?

    init(
        hostProvider: ProductHostProviding,
        logger: LoggerProtocol
    ) {
        self.hostProvider = hostProvider
        self.logger = logger
    }

    func resolveBrowseHost() {
        Task { [weak self] in
            guard let self else { return }

            do {
                #if IOS_PASEO_E2E && targetEnvironment(simulator)
                    // The launcher names the product to open. Resolved here rather than in the
                    // wireframe: `host(rawString:)` is synchronous and returns nil until the TLD
                    // provider is warm, which silently fell back to the default browse host.
                    if let raw = ProcessInfo.processInfo.environment["TRUAPI_IOS_E2E_PRODUCT_HOST"] {
                        await notify(host: try await hostProvider.resolveHost(rawString: raw))
                        return
                    }
                #endif

                let host = try await hostProvider.resolveHost(label: AppConfig.DotNs.dotNsBrowse)
                await notify(host: host)
            } catch {
                logger.error("Failed to resolve browse host: \(error)")
                await notify(host: nil)
            }
        }
    }
}

// MARK: - Private

private extension BrowseInteractor {
    @MainActor
    func notify(host: ProductHost?) {
        if let host {
            presenter?.didResolve(host: host)
        } else {
            presenter?.didFailResolving()
        }
    }
}
