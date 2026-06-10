import UIKitExt

protocol BackupViewProtocol: ControllerBackedProtocol {
    func updateViewModel(_ viewModel: BackupViewModel)
}

protocol BackupPresenterProtocol: AnyObject {
    func setup()
    func handleButtonTap(type: BackupButtonsView.ButtonType)
}

protocol BackupInteractorInputProtocol: AnyObject {
    func checkBackupStatus()
    func backupMnemonic()
}

protocol BackupInteractorOutputProtocol: AnyObject {
    func didReceiveBackupStatus(_ status: BackupViewModel.BackupStatusType)
    func didReceiveBackupComplete(with result: Result<Void, Error>)
}

protocol BackupWireframeProtocol: AlertPresentable, AuthorizationPresentable, ApplicationSettingsPresentable {
    func showWarning(
        from view: (any BackupViewProtocol)?,
        action: @escaping () -> Void
    )
    func showEnableCloud(from view: BackupViewProtocol?)
    func openSecretRecoveryPhase(from view: BackupViewProtocol?)
}
