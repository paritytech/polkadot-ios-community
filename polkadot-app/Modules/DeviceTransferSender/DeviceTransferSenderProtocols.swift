import PolkadotUI
import UIKitExt

@MainActor
protocol DeviceTransferSenderViewProtocol: ControllerBackedProtocol {
    func didReceive(screen: DeviceTransferSenderScreen, newPhone: DeviceTransferPhone)
}

@MainActor
protocol DeviceTransferSenderPresenterProtocol: AnyObject {
    func setup()
    func cancelTransfer()
    func confirmCancelTransfer()
    func backToChats()
}

@MainActor
protocol DeviceTransferSenderInteractorInputProtocol: AnyObject {
    func start(_ request: DeviceTransferRequest)
    func cancel()
}

@MainActor
protocol DeviceTransferSenderInteractorOutputProtocol: AnyObject {
    func didReceive(state: DeviceTransferState)
    func didHandOver()
}

@MainActor
protocol DeviceTransferSenderWireframeProtocol: AnyObject {
    func complete()
    func showConfirmation(
        _ viewModel: DeviceTransferConfirmationViewLayout.ViewModel,
        from view: DeviceTransferSenderViewProtocol?,
        onConfirm: @escaping () -> Void
    )
    func completeAfterFailure(from view: DeviceTransferSenderViewProtocol?)
}
