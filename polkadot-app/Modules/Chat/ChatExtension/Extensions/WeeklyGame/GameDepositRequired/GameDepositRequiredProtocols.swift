import Foundation
import SubstrateSdk
import UIKitExt

struct GameDepositRequiredModel {
    let depositHandler: () -> Void
    let cancelHandler: () -> Void
}

protocol GameDepositRequiredViewProtocol: ControllerBackedProtocol {
    func didReceive(amountString: String)
}

protocol GameDepositRequiredPresenterProtocol: AnyObject {
    func setup()
    func didTapDeposit()
    func didDismiss()
}
