import Foundation
import PolkadotUI
import Products
import UIKitExt

protocol AppDetailViewProtocol: ControllerBackedProtocol {
    func didReceive(name: String)
}

@MainActor
protocol AppDetailPresenterProtocol: AnyObject {
    func setup()
    func didTapPermissions()
}

@MainActor
protocol AppDetailWireframeProtocol: AnyObject {
    func showPermissions(
        productId: ProductId,
        productName: String,
        from view: AppDetailViewProtocol?
    )
}
