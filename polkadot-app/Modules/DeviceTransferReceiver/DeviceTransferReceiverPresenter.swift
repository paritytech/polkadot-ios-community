import Foundation
import PolkadotUI

final class DeviceTransferReceiverPresenter {
    weak var view: DeviceTransferReceiverViewProtocol?
    let wireframe: DeviceTransferReceiverWireframeProtocol
    let interactor: DeviceTransferReceiverInteractorInputProtocol

    init(
        interactor: DeviceTransferReceiverInteractorInputProtocol,
        wireframe: DeviceTransferReceiverWireframeProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension DeviceTransferReceiverPresenter: DeviceTransferReceiverPresenterProtocol {
    func setup() {
        provideViewModel()
    }
}

extension DeviceTransferReceiverPresenter: DeviceTransferReceiverInteractorOutputProtocol {}

private extension DeviceTransferReceiverPresenter {
    func provideViewModel() {}
}
