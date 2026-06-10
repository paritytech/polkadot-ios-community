import UIKit
import UIKitExt

protocol ApplicationSettingsPresentable {
    func askOpenApplicationSettings(
        with message: String,
        title: String?,
        from view: ControllerBackedProtocol?
    )

    func openApplicationSettings()
}

extension ApplicationSettingsPresentable {
    func askOpenApplicationSettings(
        with message: String,
        title: String?,
        from view: ControllerBackedProtocol?
    ) {
        var currentController = view?.controller

        if currentController == nil {
            currentController = UIApplication.shared.delegate?.window??.rootViewController
        }

        guard let controller = currentController else {
            return
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let closeTitle = String(localized: .Common.notNow)
        let closeAction = UIAlertAction(title: closeTitle, style: .cancel, handler: nil)

        let settingsTitle = String(localized: .Common.openSettings)
        let settingsAction = UIAlertAction(title: settingsTitle, style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }

        alert.addAction(closeAction)
        alert.addAction(settingsAction)

        controller.present(alert, animated: true, completion: nil)
    }

    func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
