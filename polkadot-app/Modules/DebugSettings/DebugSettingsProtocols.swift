import Foundation
import UIKitExt

protocol DebugSettingsViewProtocol: ControllerBackedProtocol {
    func didReceive(canClearBackup: Bool)
    func didReceive(canClearReferral: Bool)
    func didReceive(hasJWTToken: Bool)
}

protocol DebugSettingsPresenterProtocol: AnyObject {
    func setup()
    func clearBackup()
    func clearReferral()
    func clearJWTToken()
    func shareLogs()
    func showProducts()
    func showDotNsBrowser()
    func replaceWithRandomEntropy()
    func showThemeSelection()
}

protocol DebugSettingsInteractorInputProtocol: AnyObject {
    func setup()
    func clearBackup()
    func clearReferral()
    func clearJWTToken()
    func makeLogsDraft() -> EmailDraft?
    func replaceWithRandomEntropy()
}

@MainActor
protocol DebugSettingsInteractorOutputProtocol: AnyObject {
    func didReceive(canClearBackup: Bool)
    func didReceive(canClearReferral: Bool)
    func didReceive(hasJWTToken: Bool)
}

protocol DebugSettingsWireframeProtocol: AnyObject {
    func showProducts(from view: ControllerBackedProtocol?)
    func showDotNsBrowser(from view: ControllerBackedProtocol?)
    func showThemeSelection(from view: ControllerBackedProtocol?)
}
