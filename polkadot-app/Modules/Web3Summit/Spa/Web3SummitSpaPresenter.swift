import Foundation

@MainActor
final class Web3SummitSpaPresenter {
    weak var view: Web3SummitSpaViewProtocol?
    let wireframe: Web3SummitSpaWireframeProtocol
    let interactor: Web3SummitSpaInteractorProtocol
    let isSkippable: Bool
    let logger: LoggerProtocol

    private var pollTask: Task<Void, Never>?

    init(
        interactor: Web3SummitSpaInteractor,
        wireframe: Web3SummitSpaWireframeProtocol,
        isSkippable: Bool,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.isSkippable = isSkippable
        self.logger = logger
    }

    deinit {
        pollTask?.cancel()
    }
}

extension Web3SummitSpaPresenter: Web3SummitSpaPresenterProtocol {
    func setup() {
        view?.didReceive(isSkippable: isSkippable)

        pollTask = Task { [weak self, interactor] in
            do {
                for try await status in interactor.attendanceStatusUpdates() {
                    self?.view?.didReceive(attendanceStatus: status)
                }
            } catch {
                self?.logger.error("Failed on awaiting attendance confirmation: \(error)")
            }
        }
    }

    func didTapStart() {
        wireframe.proceed()
    }

    func didTapSkip() {
        interactor.markVerifiedManually()
        wireframe.proceed()
    }
}
