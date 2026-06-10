import UIKit
import SwiftUI
import PolkadotUI
import DesignSystem

enum Web3SummitHardGateViewFactory {
    @MainActor
    static func createEndedView() -> UIViewController {
        createController(
            with: AnimatedTextPlaceholderView(text: String(localized: .web3SummitEnded))
        )
    }

    @MainActor
    static func createNotStartedView() -> UIViewController {
        createController(
            with: AnimatedTextPlaceholderView(text: String(localized: .web3SummitNotStarted))
        )
    }

    private static func createController(with rootView: some View) -> UIViewController {
        let controller = UIHostingController(rootView: rootView)
        controller.view.backgroundColor = .bgSurfaceMain
        return controller
    }
}
