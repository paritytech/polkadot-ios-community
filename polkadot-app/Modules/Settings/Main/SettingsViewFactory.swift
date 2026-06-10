import Foundation
import Keystore_iOS
import Foundation_iOS
import DesignSystem

@MainActor
enum SettingsViewFactory {
    static func createView(
        serviceCoordinator: ServiceCoordinatorProtocol
    ) -> SettingsViewProtocol? {
        let emailComposeAdapter = EmailComposeAdapter()
        let interactor = SettingsInteractor(
            logger: Logger.shared,
            mnemonicBackupHelper: MnemonicBackupHelper(),
            emailComposePresenter: emailComposeAdapter
        )

        let wireframe = SettingsWireframe(
            serviceCoordinator: serviceCoordinator,
            emailComposePresenter: emailComposeAdapter
        )
        let presenter = SettingsPresenter(
            interactor: interactor,
            wireframe: wireframe,
            viewModelFactory: SettingsViewModelFactory(),
            themeManager: ThemeManager.shared
        )

        let view = SettingsViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
