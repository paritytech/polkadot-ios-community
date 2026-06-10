import Foundation
import PolkadotUI
import Keystore_iOS

final class PolkadotSigningPresenter {
    weak var view: PolkadotSigningViewProtocol?

    private let interactor: PolkadotSigningInteractorInputProtocol
    private let wireframe: PolkadotSigningWireframeProtocol

    private var parsedResult: PolkadotParsedSigningRequestResult?
    private var isInProgress = false
    private var isFailed = false

    init(
        interactor: PolkadotSigningInteractorInputProtocol,
        wireframe: PolkadotSigningWireframeProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension PolkadotSigningPresenter: PolkadotSigningPresenterProtocol {
    func setup() {
        interactor.setup()
        provideViewModel()
    }

    func sign() {
        guard let parsedResult else {
            return
        }
        interactor.signParsedResult(parsedResult)
    }

    func cancel() {
        interactor.reject()
    }

    func viewDetails() {
        guard let parsedResult else {
            return
        }
        wireframe.showViewDetails(
            with: parsedResult.detailsText,
            isTransaction: parsedResult.isTransaction,
            view: view
        )
    }
}

extension PolkadotSigningPresenter: PolkadotSigningInteractorOutputProtocol {
    func didStartParsingRequest() {
        markAsInProgress()
    }

    func didFinishParsingRequest(with result: PolkadotParsedSigningRequestResult) {
        parsedResult = result
        isInProgress = false
        provideViewModel()
    }

    func didFailToParseRequest(with _: Error) {
        markAsFailed()
    }

    func didStartSigning() {
        markAsInProgress()
    }

    func didFinishSigning() {
        wireframe.hide(view: view)
    }

    func didFailToSign(with error: Error) {
        handleResultSubmissionError(error)
    }

    func didStartRejecting() {
        markAsInProgress()
    }

    func didFinishRejecting() {
        wireframe.hide(view: view)
    }

    func didFailToReject(with error: Error) {
        handleResultSubmissionError(error)
    }
}

private extension PolkadotSigningPresenter {
    func markAsInProgress() {
        isInProgress = true
        provideViewModel()
    }

    func unmarkAsInProgress() {
        isInProgress = false
        provideViewModel()
    }

    func markAsFailed() {
        isInProgress = false
        isFailed = true
        provideViewModel()
    }

    func handleResultSubmissionError(_ error: Error) {
        if let knownError = error as? PolkadotHostMessageError {
            switch knownError {
            case .submissionFailed:
                unmarkAsInProgress()

                wireframe.present(
                    message: String(localized: .polkadotHostPostError),
                    title: String(localized: .Common.error),
                    closeAction: String(localized: .Common.close),
                    from: view
                )
            case let .messageTooBig(maxSize, actualSize):
                unmarkAsInProgress()

                wireframe.present(
                    message: String(
                        localized: .polkadotHostMessageTooBigError(
                            actualSize: ByteSizeFormatter.string(fromBytes: actualSize),
                            maxSize: ByteSizeFormatter.string(fromBytes: maxSize)
                        )
                    ),
                    title: String(localized: .Common.error),
                    closeAction: String(localized: .Common.close),
                    from: view
                )
            default:
                markAsFailed()
            }
        } else {
            markAsFailed()
        }
    }

    func provideViewModel() {
        if isFailed {
            view?.didReceive(viewModel: .failure(
                .init(localized: .polkadotSigningFailure)
            ))
        } else if isInProgress {
            view?.didReceive(viewModel: .inProgress)
        } else if let parsedResult {
            view?.didReceive(viewModel: .result(.init(
                hostName: parsedResult.requester.name,
                iconViewModel: parsedResult.requester.iconUrl.map {
                    RemoteImageViewModel(url: $0)
                },
                transactionDescription: parsedResult.parsedRequest.descriptionText
            )))
        }
    }
}
