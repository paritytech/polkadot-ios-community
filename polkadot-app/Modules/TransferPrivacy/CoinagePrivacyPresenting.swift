import UIKitExt

protocol CoinagePrivacyPresenting {
    func showDegradedPrivacy(
        model: TransferPrivacyModel,
        from view: (any ControllerBackedProtocol)?,
        onSendDegraded: @escaping () -> Void,
        onSendNonDegraded: @escaping () -> Void
    )
}

extension CoinagePrivacyPresenting {
    func showDegradedPrivacy(
        model: TransferPrivacyModel,
        from view: (any ControllerBackedProtocol)?,
        onSendDegraded: @escaping () -> Void,
        onSendNonDegraded: @escaping () -> Void
    ) {
        let sheetView = TransferPrivacyViewFactory.createView(
            from: model,
            onSendDegraded: onSendDegraded,
            onSendNonDegraded: onSendNonDegraded,
            onCancel: { [weak view] in view?.controller.dismiss(animated: true) }
        )
        view?.controller.present(sheetView, animated: true)
    }
}
