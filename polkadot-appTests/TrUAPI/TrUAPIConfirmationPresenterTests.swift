import Foundation
import Testing
import UIKit
import UIKitExt
import Products
import TrUAPIHost

@testable import polkadot_app

@MainActor
struct TrUAPIConfirmationPresenterTests {
    /// Anchor that records the prompt scope bound when a prompt is presented,
    /// without presenting anything.
    private final class ScopeCapturingAnchor: UIViewController, ControllerBackedProtocol {
        private(set) var presentedScope: PromptPresentationScope?

        override func present(_: UIViewController, animated _: Bool, completion _: (() -> Void)? = nil) {
            presentedScope = PromptPresentationScope.current
        }
    }

    @Test("Cancelling a confirmation withdraws the prompt it presented")
    func cancellationClosesPresentedPrompt() async throws {
        let anchor = ScopeCapturingAnchor()
        let routers = ProductRoutersFacade.sso()
        routers.setPresentationView(anchor)
        let presenter = TrUAPIConfirmationPresenter(routerFacade: routers, logger: MockLogger())

        let task = Task {
            await presenter.confirm(
                review: .productSubtree(ProductSubtreeReview(productId: "test.product")),
                from: "test.product"
            )
        }
        for _ in 0 ..< 100 where anchor.presentedScope == nil {
            await Task.yield()
        }
        let scope = try #require(anchor.presentedScope)
        #expect(!scope.isWithdrawn)

        task.cancel()
        let verdict = await task.value
        for _ in 0 ..< 100 where !scope.isWithdrawn {
            await Task.yield()
        }

        #expect(!verdict)
        #expect(scope.isWithdrawn)
    }
}
