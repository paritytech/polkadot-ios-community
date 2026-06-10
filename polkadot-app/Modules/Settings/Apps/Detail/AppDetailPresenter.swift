import Foundation
import Products

final class AppDetailPresenter {
    weak var view: AppDetailViewProtocol?

    private let wireframe: AppDetailWireframeProtocol
    private let productId: ProductId

    init(
        productId: ProductId,
        wireframe: AppDetailWireframeProtocol
    ) {
        self.productId = productId
        self.wireframe = wireframe
    }
}

extension AppDetailPresenter: AppDetailPresenterProtocol {
    func setup() {
        view?.didReceive(name: productId)
    }

    func didTapPermissions() {
        wireframe.showPermissions(
            productId: productId,
            productName: productId,
            from: view
        )
    }
}
