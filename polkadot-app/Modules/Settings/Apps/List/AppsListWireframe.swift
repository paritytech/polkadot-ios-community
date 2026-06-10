import Foundation
import Products

final class AppsListWireframe: AppsListWireframeProtocol {
    func showAppDetail(productId: ProductId, from view: AppsListViewProtocol?) {
        guard let detailView = AppDetailViewFactory.createView(productId: productId) else {
            return
        }

        view?.controller.navigationController?.pushViewController(
            detailView.controller,
            animated: true
        )
    }
}
