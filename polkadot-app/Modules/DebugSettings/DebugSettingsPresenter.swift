import Foundation
import UIKit

final class DebugSettingsPresenter {
    weak var view: DebugSettingsViewProtocol?

    let wireframe: DebugSettingsWireframeProtocol
    let interactor: DebugSettingsInteractorInputProtocol
    let shareActivityPresenter: ShareActivityPresenting
    let emailComposePresenter: EmailComposePresenting

    init(
        interactor: DebugSettingsInteractorInputProtocol,
        wireframe: DebugSettingsWireframeProtocol,
        shareActivityPresenter: ShareActivityPresenting,
        emailComposePresenter: EmailComposePresenting
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.shareActivityPresenter = shareActivityPresenter
        self.emailComposePresenter = emailComposePresenter
    }
}

extension DebugSettingsPresenter: DebugSettingsPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func clearBackup() {
        interactor.clearBackup()
    }

    func clearReferral() {
        interactor.clearReferral()
    }

    func clearJWTToken() {
        interactor.clearJWTToken()
    }

    func shareLogs() {
        guard let draft = interactor.makeLogsDraft() else {
            return
        }

        if emailComposePresenter.canSendMail() {
            emailComposePresenter.presentEmail(with: draft) { _ in }
        } else if let attachment = draft.attachment {
            shareActivityPresenter.share(activityItems: [attachment.url]) { _ in }
        }
    }

    func showProducts() {
        wireframe.showProducts(from: view)
    }

    func showDotNsBrowser() {
        wireframe.showDotNsBrowser(from: view)
    }

    func showThemeSelection() {
        wireframe.showThemeSelection(from: view)
    }

    func replaceWithRandomEntropy() {
        let alert = UIAlertController(
            title: "Replace Entropy",
            message: "This will replace the root entropy with a new random one.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Replace", style: .destructive) { [weak self] _ in
            self?.interactor.replaceWithRandomEntropy()
        })

        view?.controller.present(alert, animated: true)
    }
}

extension DebugSettingsPresenter: DebugSettingsInteractorOutputProtocol {
    func didReceive(canClearBackup: Bool) {
        view?.didReceive(canClearBackup: canClearBackup)
    }

    func didReceive(canClearReferral: Bool) {
        view?.didReceive(canClearReferral: canClearReferral)
    }

    func didReceive(hasJWTToken: Bool) {
        view?.didReceive(hasJWTToken: hasJWTToken)
    }
}
