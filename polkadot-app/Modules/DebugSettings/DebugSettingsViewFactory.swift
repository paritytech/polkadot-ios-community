import Foundation
import KeyDerivation
import Keystore_iOS

enum DebugSettingsViewFactory {
    static func createView() -> DebugSettingsViewProtocol? {
        let interactor = DebugSettingsInteractor(
            mnemonicBackupHelper: MnemonicBackupHelper(),
            logsDraftFactory: LogsEmailDraftFactory(),
            keystore: Keychain(),
            entropyManager: RootEntropyManager.shared
        )
        let shareActivityPresenter = ShareActivityAdapter()
        let emailComposePresenter = EmailComposeAdapter()
        let wireframe = DebugSettingsWireframe()
        let presenter = DebugSettingsPresenter(
            interactor: interactor,
            wireframe: wireframe,
            shareActivityPresenter: shareActivityPresenter,
            emailComposePresenter: emailComposePresenter
        )
        let view = DebugSettingsViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter
        shareActivityPresenter.use(presenter: view)
        emailComposePresenter.use(presenter: view)

        return view
    }
}
