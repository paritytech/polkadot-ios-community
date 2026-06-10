import Foundation
import Products

final class AppsListInteractor {
    weak var presenter: AppsListInteractorOutputProtocol?

    private let providerFactory: ProductPermissionDataProviderMaking
    private let logger: LoggerProtocol

    private var subscriptionTask: Task<Void, Never>?

    init(
        providerFactory: ProductPermissionDataProviderMaking,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.providerFactory = providerFactory
        self.logger = logger
    }

    deinit {
        subscriptionTask?.cancel()
    }
}

extension AppsListInteractor: AppsListInteractorInputProtocol {
    func setup() {
        subscriptionTask = Task { [weak self, providerFactory, logger] in
            let stream = providerFactory.subscribeAllGrants(grantedOnly: true)

            do {
                for try await grants in stream {
                    let productIds = Self.distinctProductIds(from: grants)
                    await self?.presenter?.didReceive(productIds: productIds)
                }
            } catch {
                logger.error("Apps list subscription error: \(error)")
            }
        }
    }
}

private extension AppsListInteractor {
    static func distinctProductIds(from grants: [ProductPermissionGrant]) -> [ProductId] {
        var seen = Set<ProductId>()
        return grants.compactMap { grant in
            seen.insert(grant.productId).inserted ? grant.productId : nil
        }
    }
}
