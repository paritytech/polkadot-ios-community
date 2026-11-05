import Foundation
import PolkadotUI

@MainActor
final class DeviceTransferReceiverPresenter {
    weak var view: DeviceTransferReceiverViewProtocol?
    let wireframe: DeviceTransferReceiverWireframeProtocol
    let interactor: DeviceTransferReceiverInteractorInputProtocol

    private var screen: DeviceTransferReceiverScreen = .start
    private var oldPhone: DeviceTransferOldPhone?
    /// Kept so the bar doesn't empty while the connection is replaced.
    private var lastProgress: Double = 0
    private var oldPhoneSilent = false
    private var offersActivation = false

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
        interactor.setup()
        provideScreen()
    }

    func startTransfer() {
        lastProgress = 0
        interactor.startTransfer()
    }

    func cancelTransfer() {
        interactor.cancelTransfer()
    }

    func activateWithoutTransfer() {
        interactor.activateWithoutTransfer()
    }

    func complete() {
        wireframe.complete()
    }
}

extension DeviceTransferReceiverPresenter: DeviceTransferReceiverInteractorOutputProtocol {
    func didReceive(state: DeviceTransferState) {
        screen = screen(for: state)
        if screen != .waiting {
            oldPhoneSilent = false
        }
        provideScreen()
        provideActivationOffer()
    }

    func didReceive(oldPhone installation: ActiveInstallation?) {
        oldPhone = installation.map {
            DeviceTransferOldPhone(model: $0.deviceModel, operatingSystem: $0.operatingSystem)
        }
        provideScreen()
    }

    func didWaitTooLongForOldPhone() {
        oldPhoneSilent = true
        provideActivationOffer()
    }

    func didActivateWithoutTransfer() {
        wireframe.complete()
    }

    func didFailActivation() {
        wireframe.present(
            message: String(localized: .deviceTransferActivationFailed),
            title: String(localized: .Common.error),
            closeAction: String(localized: .Common.close),
            from: view
        )
    }
}

private extension DeviceTransferReceiverPresenter {
    func provideActivationOffer() {
        let offers = screen.offersActivation || (screen == .waiting && oldPhoneSilent)
        guard offers != offersActivation else { return }
        offersActivation = offers
        view?.didReceive(offersActivation: offers)
    }

    func provideScreen() {
        view?.didReceive(screen: screen, oldPhone: oldPhone)
    }

    func screen(for state: DeviceTransferState) -> DeviceTransferReceiverScreen {
        switch state {
        case .idle:
            .start
        case .waitingForSender:
            .waiting
        case .connecting:
            .connecting
        case let .syncing(applied, total):
            .syncing(progress: track(DeviceTransferProgressScale.syncing(applied: applied, total: total)))
        case let .files(progress):
            .files(
                progress: track(DeviceTransferProgressScale.files(progress)),
                receivedBytes: progress.receivedBytes,
                totalBytes: progress.totalBytes
            )
        case .reconnecting:
            .reconnecting(progress: lastProgress)
        case .finalizing:
            .finishing
        case .completed:
            .done
        case let .failed(failure):
            screen(for: failure)
        }
    }

    /// Cancelling on this phone goes back to the start; only the other phone's decisions get their own screens.
    func screen(for failure: DeviceTransferFailure) -> DeviceTransferReceiverScreen {
        switch failure {
        case .cancelled:
            .start
        case .rejected:
            .declined
        case .aborted(.userCancelled):
            .cancelledOnOldPhone
        case .expired,
             .aborted,
             .timedOut,
             .failed:
            .failed
        }
    }

    func track(_ progress: Double) -> Double {
        lastProgress = progress
        return progress
    }
}

private extension DeviceTransferReceiverScreen {
    /// Screens where the old phone may be out of reach, so activating without it is offered.
    var offersActivation: Bool {
        switch self {
        case .declined,
             .cancelledOnOldPhone,
             .failed:
            true
        default:
            false
        }
    }
}

/// Data fills the first fifth of the bar and files the rest, so the bar never moves back between phases.
enum DeviceTransferProgressScale {
    static let dataShare = 0.2

    static func syncing(applied: Int, total: Int) -> Double {
        dataShare * ratio(Double(applied), of: Double(total))
    }

    static func files(_ progress: DeviceTransferFileProgress) -> Double {
        dataShare + (1 - dataShare) * ratio(Double(progress.receivedBytes), of: Double(progress.totalBytes))
    }

    private static func ratio(_ part: Double, of whole: Double) -> Double {
        whole > 0 ? min(part / whole, 1) : 1
    }
}
