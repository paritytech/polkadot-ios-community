import Foundation
import UIKit
import UIKitExt

struct GameAlarmSettingsModel {
    let onUpdate: () -> Void
}

struct GameAlarmSettingsOption {
    let seconds: Int
    let label: String
    let image: UIImage?
}

protocol GameAlarmSettingsViewProtocol: ControllerBackedProtocol {
    func didReceive(options: [GameAlarmSettingsOption])
}

protocol GameAlarmSettingsPresenterProtocol: AnyObject {
    func setup()
    func didSelect(seconds: Int)
}

protocol GameAlarmSettingsInteractorInputProtocol: AnyObject {
    func setup()
    func save(seconds: Int)
}

protocol GameAlarmSettingsInteractorOutputProtocol: AnyObject {
    func didReceive(options: [Int], currentSeconds: Int)
    func didSave()
}
