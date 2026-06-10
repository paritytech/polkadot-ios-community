import Foundation
import UIKit
import UIKitExt

final class ClaimFullUsernameWireframe: ClaimUsernameWireframeProtocol {
    func finishFlow(from view: ControllerBackedProtocol?) {
        view?.controller.dismiss(animated: true)
    }

    func showRecovery(from _: (any ControllerBackedProtocol)?) {}
}
