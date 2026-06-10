import UIKit
import UIKitExt
import Foundation_iOS
import PolkadotUI

final class TransferAmountWireframe: TransferAmountWireframeProtocol {
    let recipient: RecipientModel

    init(recipient: RecipientModel) {
        self.recipient = recipient
    }

    func hide(view: ControllerBackedProtocol?) {
        let navigationController = view?.controller.navigationController

        navigateToChat(with: .person(recipient.accountId), force: false)
        navigationController?.popToRootViewController(animated: false)
    }

    func showDegradedPrivacy(
        model: TransferPrivacyModel,
        from view: (any ControllerBackedProtocol)?,
        onSendDegraded: @escaping () -> Void,
        onSendNonDegraded: @escaping () -> Void
    ) {
        let sheetView = TransferPrivacyViewFactory.createView(
            from: model,
            onSendDegraded: onSendDegraded,
            onSendNonDegraded: onSendNonDegraded
        )
        view?.controller.present(sheetView, animated: true)
    }

    func showBalanceInfo(model: BalanceInfoModel, from view: (any ControllerBackedProtocol)?) {
        let sheet = BalanceInfoViewFactory.createView(from: model)
        view?.controller.present(sheet, animated: true)
    }
}
