import Foundation
import Products

enum AppDetailViewFactory {
    static func createView(productId: ProductId) -> AppDetailViewProtocol? {
        let wireframe = AppDetailWireframe()

        let presenter = AppDetailPresenter(
            productId: productId,
            wireframe: wireframe
        )

        let view = AppDetailViewController(presenter: presenter)

        presenter.view = view

        return view
    }
}
