import Foundation

enum GameResultsWebViewFactory {
    static let fallbackURL = CIKeys.gameResultsFallbackURL.asConfigURL

    static func createView(
        url: URL,
        input: GameResultsInput,
        onClose: @escaping () -> Void
    ) -> GameResultsWebViewController? {
        GameResultsWebViewController(url: url, input: input, onClose: onClose)
    }

    static func createPreloadedView(url: URL) -> GameResultsWebViewController? {
        GameResultsWebViewController(url: url, input: nil)
    }
}
