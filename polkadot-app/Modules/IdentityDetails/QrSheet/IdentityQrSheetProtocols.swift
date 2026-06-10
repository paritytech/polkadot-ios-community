import UIKitExt
import PolkadotUI

protocol IdentityQrSheetViewProtocol: ControllerBackedProtocol {
    var viewModel: IdentityDetailsViewModel { get }
}

protocol IdentityQrSheetPresenterProtocol: AnyObject {
    func setup()
    func close()
}

protocol IdentityQrSheetWireframeProtocol: AnyObject {
    func close(from view: IdentityQrSheetViewProtocol?)
}
