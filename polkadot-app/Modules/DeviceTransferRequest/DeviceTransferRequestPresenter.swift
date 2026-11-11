import Foundation
import PolkadotUI

@MainActor
final class DeviceTransferRequestPresenter {
    weak var view: DeviceTransferRequestViewProtocol?
    let wireframe: DeviceTransferRequestWireframeProtocol
    let interactor: DeviceTransferRequestInteractorInputProtocol

    private var request: DeviceTransferRequest
    /// Set once the user answers, so the request leaving the listener afterwards isn't reported as withdrawn.
    private var isAnswered = false

    init(
        request: DeviceTransferRequest,
        interactor: DeviceTransferRequestInteractorInputProtocol,
        wireframe: DeviceTransferRequestWireframeProtocol
    ) {
        self.request = request
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension DeviceTransferRequestPresenter: DeviceTransferRequestPresenterProtocol {
    func setup() {
        provideNewPhone()
        interactor.setup()
    }

    func transfer() {
        guard !isAnswered else { return }
        interactor.countPendingPayments()
    }

    func decline() {
        guard !isAnswered else { return }
        isAnswered = true
        interactor.decline(request)
    }
}

extension DeviceTransferRequestPresenter: DeviceTransferRequestInteractorOutputProtocol {
    func didReceive(pendingRequest: DeviceTransferRequest?) {
        guard !isAnswered else { return }

        guard let pendingRequest else {
            isAnswered = true
            wireframe.closeAsWithdrawn(from: view)
            return
        }

        if pendingRequest != request {
            request = pendingRequest
            provideNewPhone()
        }
    }

    func didReceive(pendingPayments: PendingPayments) {
        guard !isAnswered else { return }

        if pendingPayments.isEmpty {
            confirmTransfer()
        } else {
            wireframe.showPendingPayments(pendingPayments, from: view)
        }
    }

    func didDecline() {
        wireframe.close(from: view)
    }
}

private extension DeviceTransferRequestPresenter {
    func confirmTransfer() {
        guard !isAnswered else { return }
        isAnswered = true
        wireframe.confirm(request, from: view)
    }

    func provideNewPhone() {
        let newPhone = DeviceTransferPhone(model: request.deviceModel, operatingSystem: request.operatingSystem)
        view?.didReceive(newPhone: newPhone)
    }
}
