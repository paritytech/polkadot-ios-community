import Foundation
import UIKitExt

protocol SettingsViewProtocol: ControllerBackedProtocol {
    func applyContent(_ content: SettingsViewModel.Content)
}

@MainActor
protocol SettingsPresenterProtocol: AnyObject {
    func setup()
    func didTapCell(_ cell: SettingsViewModel.CellType)
}

protocol SettingsInteractorInputProtocol: AnyObject {
    func setup()
    func openMailApp()
}

@MainActor
protocol SettingsInteractorOutputProtocol: AnyObject {
    func didReceiveAppVersion(_ appInfo: (version: String, build: String))
    func didReceiveBackupAttention(isRequired: Bool)
    func didReceiveSelectedCurrency(_ code: String)
    func didOpenMailApp()
    func didFailToOpenMailApp(email: String)
    func didReceiveHasBlockedUsers(_ hasBlockedUsers: Bool)
}

@MainActor
protocol SettingsWireframeProtocol: AnyObject, WebPresentable, AlertPresentable {
    func showBackupFlow(from view: SettingsViewProtocol?)
    func showLinkedDevices(from view: SettingsViewProtocol?)
    func showRecoverPendingTransactions(from view: SettingsViewProtocol?)
    func showCurrencyPicker(from view: SettingsViewProtocol?)
    func openMailComposer(from view: SettingsViewProtocol?)
    func showContactEmailFallback(_ email: String, from view: SettingsViewProtocol?)
    func showBlockedUsers(from view: SettingsViewProtocol?)
    func showApps(from view: SettingsViewProtocol?)
    func showThemeSelection(from view: SettingsViewProtocol?, onFinish: @escaping () -> Void)
}
