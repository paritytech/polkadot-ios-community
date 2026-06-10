import UIKitExt

protocol BalanceInfoViewProtocol: ControllerBackedProtocol {
    func didReceive(model: BalanceInfoModel)
}

protocol BalanceInfoPresenterProtocol: AnyObject {
    func setup()
    func onAvailableNowInfo()
    func onAvailableSoonInfo()
}

protocol BalanceInfoWireframeProtocol: AnyObject {
    func showAvailableNowInfo(from view: ControllerBackedProtocol?)
    func showAvailableSoonInfo(from view: ControllerBackedProtocol?)
}
