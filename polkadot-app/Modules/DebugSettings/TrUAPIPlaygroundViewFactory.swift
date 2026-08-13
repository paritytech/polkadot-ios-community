#if DEBUG
    import Foundation
    import Products
    import TrUAPIHost
    import UIKit
    import Keystore_iOS
    import KeyDerivation

    /// Debug-only assembly for the truapi playground (interactive API
    /// explorer). Presentation belongs to ``DebugSettingsWireframe``.
    enum TrUAPIPlaygroundViewFactory {
        static let playgroundProductId: ProductId = "truapi-playground.dot"
        static let playgroundURL = URL(string: "http://localhost:3000")

        /// The playground as a direct-URL rust-runtime SPA. Forces rust mode
        /// (no flag read); the shared runtime and its production session are
        /// sourced from the process-wide provider inside `createRustView`.
        @MainActor
        static func createView(logger: LoggerProtocol = Logger.shared) -> SPAViewProtocol? {
            guard let url = playgroundURL else {
                return nil
            }

            guard let flowState = SPAFlowState.create() else {
                logger.error("Playground: SPA flow state unavailable (chains not set up)")
                return nil
            }

            guard let host = ProductHost(rawString: playgroundProductId) else {
                return nil
            }

            let configuration = SPAConfiguration(
                title: "TrUAPI Playground",
                isRootScreen: false,
                showMoreButton: false,
                page: ProductPage(host: host),
                contentSource: .directURL(url)
            )

            return SPAViewFactory.createRustView(
                configuration: configuration,
                flowState: flowState
            )
        }
    }
#endif
