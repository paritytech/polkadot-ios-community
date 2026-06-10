import Foundation
import Foundation_iOS
import UIKitExt

protocol AccountRecoveryViewProtocol: ControllerBackedProtocol {
    func didReceive(inputViewModel: InputViewModelProtocol)
}

protocol AccountRecoveryPresenterProtocol: AnyObject {
    func setup()
    func proceed()
}

protocol AccountRecoveryInteractorInputProtocol: AnyObject {
    func proceed(withWords words: String)
}

protocol AccountRecoveryInteractorOutputProtocol: AnyObject {
    func didRestoreWallets()
    func didReceiveInvalidMnemonicFormat()
    func didDecideBroken()
    func authorizeUser(completion: @escaping AuthorizationCompletionBlock)
}

protocol AccountRecoveryWireframeProtocol: BottomSheetErrorPresentable, AuthorizationPresentable {
    func didDecideBroken()
    func didRestoreWallets()
}
