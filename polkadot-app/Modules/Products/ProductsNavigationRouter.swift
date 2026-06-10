import UIKit
import Products
import UIKitExt

@MainActor
protocol ProductsNavigationRouting: AnyObject {
    func navigateTo(destination: ProductHost) async throws
    func openExternalURL(_ url: URL) async throws
}

@MainActor
final class ProductsNavigationRouter: ProductsNavigationRouting {
    private weak var presentationView: ControllerBackedProtocol?
    private var flowState: SPAFlowState?

    nonisolated init() {}

    func setPresentationView(_ view: ControllerBackedProtocol) {
        presentationView = view
    }

    func setFlowState(_ flowState: SPAFlowState) {
        self.flowState = flowState
    }

    func navigateTo(destination: ProductHost) async throws {
        guard
            let view = presentationView,
            let flowState
        else { return }

        guard let spaView = SPAViewFactory.createView(
            productHost: destination,
            flowState: flowState
        ) else {
            return
        }

        let navigationController = SPAViewFactory.makeCardNavigationController(for: spaView)
        navigationController.modalPresentationStyle = .fullScreen
        view.controller.present(navigationController, animated: true)
    }

    func openExternalURL(_ url: URL) async throws {
        _ = await UIApplication.shared.open(url)
    }
}

@MainActor
final class ForbiddenNavigationRouter: ProductsNavigationRouting {
    nonisolated init() {}

    func navigateTo(destination _: ProductHost) async throws {
        throw ProductNativeApiError.navigationForbidden
    }

    func openExternalURL(_: URL) async throws {
        throw ProductNativeApiError.navigationForbidden
    }
}
