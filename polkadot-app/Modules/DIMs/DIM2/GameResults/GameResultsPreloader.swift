import UIKit

@MainActor
final class GameResultsPreloader {
    private let urlProvider: GameResultsURLProviding
    private var viewController: GameResultsWebViewController?
    private var isPageReady = false
    private var resolvedURL: URL?

    init(urlProvider: GameResultsURLProviding? = nil) {
        self.urlProvider = urlProvider ?? GameResultsURLProvider.makeDefault()
    }

    func start() {
        guard viewController == nil else { return }

        Task { [weak self, urlProvider] in
            let url = await urlProvider.resolveURL()
            await self?.applyResolvedURL(url)
        }
    }

    func consume(onClose: @escaping () -> Void) -> GameResultsWebViewController? {
        if let vc = viewController, isPageReady {
            viewController = nil
            isPageReady = false
            vc.onClose = onClose
            return vc
        }
        let url = resolvedURL ?? GameResultsWebViewFactory.fallbackURL
        Logger.shared
            .debug(
                "[GameDebug] preloader.consume: not ready — creating on-demand with " +
                    "\(url.isFileURL ? "file://" + url.path : url.absoluteString)"
            )
        return GameResultsWebViewFactory.createPreloadedView(url: url).map { vc in
            vc.onClose = onClose
            return vc
        }
    }
}

private extension GameResultsPreloader {
    func applyResolvedURL(_ url: URL) {
        resolvedURL = url
        guard
            viewController == nil,
            let vc = GameResultsWebViewFactory.createPreloadedView(url: url)
        else { return }

        Logger.shared
            .debug(
                "[GameDebug] preloader: warming with " +
                    "\(url.isFileURL ? "file://" + url.path : url.absoluteString)"
            )
        vc.onPageReady = { [weak self] in
            self?.isPageReady = true
        }
        viewController = vc
        _ = vc.view
    }
}
