import Foundation
import PolkadotUI

@MainActor
final class DeviceTransferSenderPresenter {
    weak var view: DeviceTransferSenderViewProtocol?
    let wireframe: DeviceTransferSenderWireframeProtocol
    let interactor: DeviceTransferSenderInteractorInputProtocol

    private let request: DeviceTransferRequest
    private var screen: DeviceTransferSenderScreen = .connecting
    /// Kept so S4 shows where the data stopped while the connection is replaced.
    private var lastDataProgress: Double?

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
    func setup() {
        provideScreen()
        interactor.start(request)
    }

    /// Data already moving needs a confirmation; connecting stops at once.
    func cancelTransfer() {
        guard screen.isTransferring else {
            interactor.cancel()
            return
        }

        wireframe.showConfirmation(.cancelSendingTransfer, from: view) { [weak self] in
            self?.confirmCancelTransfer()
        }
    }

    /// The run may have moved on while the sheet was open, so a late confirm is dropped.
    func confirmCancelTransfer() {
        guard screen.isTransferring else { return }
        interactor.cancel()
    }

    func backToChats() {
        wireframe.complete()
    }
}

extension DeviceTransferSenderPresenter: DeviceTransferSenderInteractorOutputProtocol {
    func didReceive(state: DeviceTransferState) {
        switch state {
        case .failed(.aborted(.userCancelled)):
            screen = .cancelledOnNewPhone
        case .failed(.cancelled):
            wireframe.complete()
            return
        case .failed:
            wireframe.completeAfterFailure(from: view)
            return
        default:
            screen = screen(for: state)
        }
        provideScreen()
    }

    func didHandOver() {
        wireframe.complete()
    }
}

private extension DeviceTransferSenderPresenter {
    func provideScreen() {
        let newPhone = DeviceTransferPhone(model: request.deviceModel, operatingSystem: request.operatingSystem)
        view?.didReceive(screen: screen, newPhone: newPhone)
    }

    func screen(for state: DeviceTransferState) -> DeviceTransferSenderScreen {
        switch state {
        case .idle,
             .waitingForSender,
             .connecting:
            .connecting
        case let .syncing(applied, total) where applied < total:
            .sendingData(progress: track(Double(applied) / Double(total)))
        case .syncing,
             .files:
            .sendingFiles
        case .reconnecting:
            .reconnecting(progress: screen == .sendingFiles ? nil : lastDataProgress)
        case .finalizing,
             .completed,
             .failed:
            .finishing
        }
    }

    func track(_ progress: Double) -> Double {
        lastDataProgress = progress
        return progress
    }
}

private extension DeviceTransferSenderScreen {
    var isTransferring: Bool {
        switch self {
        case .sendingData,
             .sendingFiles,
             .reconnecting:
            true
        case .connecting,
             .finishing,
             .cancelledOnNewPhone:
            false
        }
    }
}
