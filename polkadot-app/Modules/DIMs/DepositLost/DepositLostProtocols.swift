import UIKitExt

protocol DepositLostViewProtocol: AnyObject, ControllerBackedProtocol {
    func didReceive(viewModel: DepositLostViewLayout.ViewModel)
}

protocol DepositLostPresenterProtocol: AnyObject {
    func setup()
}
