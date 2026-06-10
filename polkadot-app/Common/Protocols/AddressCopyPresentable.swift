import UIKit
import UIKitExt

protocol AddressCopyPresentable {
    func copyAddress(
        from view: ControllerBackedProtocol?,
        address: String,
        locale: Locale
    )
}

extension AddressCopyPresentable {
    func copyAddress(
        from view: ControllerBackedProtocol?,
        address: String,
        locale _: Locale
    ) {
        UIPasteboard.general.string = address

        let title = String(localized: .addressCopied)

        guard let notificationView = BottomNotificationFactory.createMessageNotification(for: title) else {
            return
        }

        view?.controller.present(
            notificationView.controller,
            animated: true,
            completion: nil
        )
    }
}
