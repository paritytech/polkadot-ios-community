import Foundation
import Operation_iOS
import OperationExt
import Products

protocol GameResultsURLProviding: Sendable {
    func resolveURL() async -> URL
}

final class GameResultsURLProvider: GameResultsURLProviding, @unchecked Sendable {
    private let dotNsResolver: DotNsResolverProtocol?
    private let dotNsName: String
    private let firebaseFallback: () -> CompoundOperationWrapper<URL>
    private let bundledFallbackURL: URL
    private let logger: LoggerProtocol

    init(
        dotNsResolver: DotNsResolverProtocol?,
        dotNsName: String,
        firebaseFallback: @escaping () -> CompoundOperationWrapper<URL>,
        bundledFallbackURL: URL,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.dotNsResolver = dotNsResolver
        self.dotNsName = dotNsName
        self.firebaseFallback = firebaseFallback
        self.bundledFallbackURL = bundledFallbackURL
        self.logger = logger
    }

    func resolveURL() async -> URL {
        if let url = await resolveDotNs() {
            return url
        }

        do {
            let url = try await firebaseFallback().asyncExecute()
            logger.debug("[GameDebug] urlProvider: Firebase fallback → \(url.absoluteString)")
            return url
        } catch {
            logger
                .error(
                    "[GameDebug] urlProvider: Firebase fallback FAILED: \(error) → bundled " +
                        "\(bundledFallbackURL.absoluteString)"
                )
            return bundledFallbackURL
        }
    }
}

private extension GameResultsURLProvider {
    func resolveDotNs() async -> URL? {
        guard let dotNsResolver else {
            logger.debug("[GameDebug] urlProvider: no DotNs resolver")
            return nil
        }

        do {
            let contentDirectory = try await dotNsResolver.resolveToLocalURL(dotNsName: dotNsName)
            let indexURL = contentDirectory.appendingPathComponent("index.html")
            guard FileManager.default.fileExists(atPath: indexURL.path) else {
                logger.error(
                    "[GameDebug] urlProvider: \(dotNsName) resolved to \(contentDirectory.path) but " +
                        "index.html missing"
                )
                return nil
            }
            logger.debug("[GameDebug] urlProvider: \(dotNsName) → \(indexURL.path)")
            return indexURL
        } catch {
            logger.error("[GameDebug] urlProvider: resolve \(dotNsName) FAILED: \(error)")
            return nil
        }
    }
}

extension GameResultsURLProvider {
    static func makeDefault() -> GameResultsURLProvider {
        let resolver = SPAFlowState.create()?.dotNsResolver
        return GameResultsURLProvider(
            dotNsResolver: resolver,
            dotNsName: AppConfig.DotNs.dotNsGameWebview,
            firebaseFallback: { FirebaseApplicationService.shared.asyncWaitGameResultsFallbackURL() },
            bundledFallbackURL: GameResultsWebViewFactory.fallbackURL
        )
    }
}
