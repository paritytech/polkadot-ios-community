import Foundation
import PolkadotUI

@MainActor
final class DeviceTransferSenderPresenter {
    weak var view: DeviceTransferSenderViewProtocol?
    let wireframe: DeviceTransferSenderWireframeProtocol
    let interactor: DeviceTransferSenderInteractorInputProtocol

    private let request: DeviceTransferRequest

    init(
        request: DeviceTransferRequest,
        interactor: DeviceTransferSenderInteractorInputProtocol,
        wireframe: DeviceTransferSenderWireframeProtocol
    ) {
        self.request = request
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension DeviceTransferSenderPresenter: DeviceTransferSenderPresenterProtocol {
    func setup() {}
}

extension DeviceTransferSenderPresenter: DeviceTransferSenderInteractorOutputProtocol {}
