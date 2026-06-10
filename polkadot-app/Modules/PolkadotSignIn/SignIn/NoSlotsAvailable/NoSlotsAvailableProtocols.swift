import Foundation
import UIKitExt

protocol NoSlotsAvailableViewProtocol: ControllerBackedProtocol {
    func didReceive(message: String)
}

protocol NoSlotsAvailablePresenterProtocol: AnyObject {
    func setup()
    func dismiss()
}

protocol NoSlotsAvailableWireframeProtocol: AnyObject {
    func close(view: NoSlotsAvailableViewProtocol?)
}
