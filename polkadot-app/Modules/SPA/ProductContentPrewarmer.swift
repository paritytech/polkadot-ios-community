import Foundation
import Foundation_iOS
import Products

@MainActor
protocol ProductContentPrewarming {
    func prewarm()
}

@MainActor
final class ProductContentPrewarmer {
    private let makeDomain: () -> String
    private let chainRegistryClosure: ChainRegistryLazyClosure
    private let makeResolver: () -> DotNsResolverProtocol?
    private let logger: LoggerProtocol

    private var prewarmTask: Task<Void, Never>?

    init(
        makeDomain: @escaping () -> String,
        chainRegistryClosure: @escaping ChainRegistryLazyClosure,
        makeResolver: @escaping () -> DotNsResolverProtocol?,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.makeDomain = makeDomain
        self.chainRegistryClosure = chainRegistryClosure
        self.makeResolver = makeResolver
        self.logger = logger
    }

    deinit {
        prewarmTask?.cancel()
    }
}

extension ProductContentPrewarmer: ProductContentPrewarming {
    func prewarm() {
        guard prewarmTask == nil else { return }

        prewarmTask = Task { [weak self] in
            await self?.warmContent()
            self?.prewarmTask = nil
        }
    }
}

private extension ProductContentPrewarmer {
    func warmContent() async {
        // Resolved lazily: the domain may depend on remote config that isn't available yet at
        // prewarmer construction. By warm time the prewarm trigger has run past remote config.
        let domain = makeDomain()

        guard !domain.isEmpty else {
            logger.error("Product prewarm skipped: empty domain")
            return
        }

        await chainRegistryClosure().asyncWaitChainsSetup(for: [AppConfig.Chains.assethubChain])

        guard let resolver = makeResolver() else {
            logger.error("Product prewarm skipped: resolver unavailable for \(domain)")
            return
        }

        do {
            _ = try await resolver.resolveToLocalURL(dotNsName: domain)
            logger.debug("Product prewarm: warmed \(domain)")
        } catch {
            logger.error("Product prewarm: failed to warm \(domain): \(error)")
        }
    }
}
