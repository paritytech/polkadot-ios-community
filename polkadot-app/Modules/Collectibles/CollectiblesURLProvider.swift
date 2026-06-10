import Foundation
import Operation_iOS
import OperationExt
import Products

protocol CollectiblesURLProviding: Sendable {
    func resolveURL() async -> URL?
}

final class CollectiblesURLProvider: CollectiblesURLProviding, @unchecked Sendable {
    private let dotNsResolver: DotNsResolverProtocol?
    private let dotNsName: String
    private let remoteConfig: RemoteConfigManaging
    private let firebaseFallback: () -> CompoundOperationWrapper<URL>
    private let logger: LoggerProtocol

    init(
        dotNsResolver: DotNsResolverProtocol?,
        dotNsName: String,
        remoteConfig: RemoteConfigManaging,
        firebaseFallback: @escaping () -> CompoundOperationWrapper<URL>,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.dotNsResolver = dotNsResolver
        self.dotNsName = dotNsName
        self.remoteConfig = remoteConfig
        self.firebaseFallback = firebaseFallback
        self.logger = logger
    }

    func resolveURL() async -> URL? {
        guard remoteConfig.syncedCollectiblesEnabled() else {
            logger.debug("[Collectibles] urlProvider: disabled by remote config")
            return nil
        }

        if let url = await resolveDotNs() {
            return url
        }

        do {
            let url = try await firebaseFallback().asyncExecute()
            logger.debug("[Collectibles] urlProvider: Firebase fallback → \(url.absoluteString)")
            return url
        } catch {
            logger.error("[Collectibles] urlProvider: Firebase fallback FAILED: \(error)")
            return nil
        }
    }
}

private extension CollectiblesURLProvider {
    func resolveDotNs() async -> URL? {
        guard let dotNsResolver else {
            logger.debug("[Collectibles] urlProvider: no DotNs resolver")
            return nil
        }

        do {
            let contentDirectory = try await dotNsResolver.resolveToLocalURL(dotNsName: dotNsName)
            let indexURL = contentDirectory.appendingPathComponent("index.html")
            guard FileManager.default.fileExists(atPath: indexURL.path) else {
                logger
                    .error(
                        "[Collectibles] urlProvider: \(dotNsName) resolved to \(contentDirectory.path) but " +
                            "index.html missing"
                    )
                return nil
            }
            logger.debug("[Collectibles] urlProvider: \(dotNsName) → \(indexURL.path)")
            return indexURL
        } catch {
            logger.error("[Collectibles] urlProvider: resolve \(dotNsName) FAILED: \(error)")
            return nil
        }
    }
}

extension CollectiblesURLProvider {
    static func makeDefault() -> CollectiblesURLProvider {
        let resolver = SPAFlowState.create()?.dotNsResolver
        return CollectiblesURLProvider(
            dotNsResolver: resolver,
            dotNsName: AppConfig.DotNs.dotNsCollectibles,
            remoteConfig: FirebaseFacade.shared,
            firebaseFallback: { FirebaseApplicationService.shared.asyncWaitCollectiblesFallbackURL() }
        )
    }
}
