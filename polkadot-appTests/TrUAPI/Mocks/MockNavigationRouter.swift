import Foundation
import Products
import UIKitExt
@testable import polkadot_app

@MainActor
final class MockNavigationRouter: ProductsNavigationRouting {
    var openedURL: URL?
    var errorToThrow: Error?

    func setPresentationView(_: ControllerBackedProtocol) {}

    var isReady: Bool { false }

    @discardableResult
    func present(view _: ControllerBackedProtocol) -> Bool { false }

    func navigateTo(destination _: ProductHost) async throws {}

    func openExternalURL(_ url: URL) async throws {
        if let error = errorToThrow { throw error }
        openedURL = url
    }
}
