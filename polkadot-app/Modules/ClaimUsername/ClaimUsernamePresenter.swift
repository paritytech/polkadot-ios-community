import Foundation
import Foundation_iOS
import Combine

final class ClaimUsernamePresenter {
    weak var view: ClaimUsernameViewProtocol?
    let wireframe: ClaimUsernameWireframeProtocol
    let interactor: ClaimUsernameInteractorInputProtocol
    let validationFactory: UsernameValidationFactoryProtocol
    let logger: LoggerProtocol
    let viewModelProvider: ClaimUsernameViewModelProviding

    private var partialNormalizedUsername: String {
        usernameViewModel?.inputHandler.normalizedValue ?? ""
    }

    private var usernameCheckResult: UsernameAvailableType?
    private var usernameViewModel: InputViewModelProtocol?

    private var availableDigits: [Int] = []
    private var selectedDigits: Int?
    private var digitsFieldState: DigitsFieldState = .hidden
    private var digitsViewModel: InputViewModelProtocol?

    private var claimCancellable: AnyCancellable?
    private var usernameCheckCancellable: AnyCancellable?

    private let prefilledUsername: Username?

    init(
        interactor: ClaimUsernameInteractorInputProtocol,
        wireframe: ClaimUsernameWireframeProtocol,
        validationFactory: UsernameValidationFactoryProtocol,
        viewModelProvider: ClaimUsernameViewModelProviding,
        prefilledUsername: Username?,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.validationFactory = validationFactory
        self.logger = logger
        self.prefilledUsername = prefilledUsername
        self.viewModelProvider = viewModelProvider
    }
}

extension ClaimUsernamePresenter {
    private func validateUsername() {
        let metadata = interactor.metadata

        DataValidationRunner(
            validators: [
                validationFactory.hasValidDigits(from: digitsFieldState),
                validationFactory.notViolatingMinLength(
                    for: partialNormalizedUsername,
                    minLength: metadata.minLength
                ),
                validationFactory.notViolatingMaxLength(
                    for: partialNormalizedUsername,
                    maxLength: metadata.maxLength
                ),
                validationFactory.notValid(from: usernameCheckResult),
                validationFactory.notTaken(from: usernameCheckResult)
            ]
        ).runValidation { [weak self] in
            self?.view?.didReceiveValidation(result: .valid)
        }
    }

    private func resetDigitsState() {
        availableDigits = []
        selectedDigits = nil
        digitsFieldState = .hidden
        digitsViewModel = nil
        view?.didReceive(digitsState: .hidden)
    }

    private func provideInputViewModel(shouldPrefill: Bool) {
        let viewModel = InputViewModel.createUsernameInputViewModel(
            for: shouldPrefill ? prefilledUsername : nil,
            metadata: interactor.metadata
        )
        usernameViewModel = viewModel
        view?.didReceive(usernameInputViewModel: viewModel)

        if shouldPrefill, prefilledUsername != nil {
            update(from: viewModel)
        }
    }

    private func doUsernameCheckUpdateIfPossible() {
        resetDigitsState()

        guard
            let usernameViewModel,
            usernameViewModel.inputHandler.completed
        else {
            view?.didStopLoading()
            usernameCheckResult = .invalid
            usernameCheckCancellable?.cancel()
            usernameCheckCancellable = nil
            validateUsername()
            return
        }

        view?.didStartLoading()

        let username = Username(value: partialNormalizedUsername)
        usernameCheckCancellable = interactor.check(
            username: username
        )
        .catch {
            Just(.error($0.localizedDescription))
        }
        .receive(on: DispatchQueue.main)
        .sink(receiveValue: { [weak self] in
            self?.didCompleteCheck(for: username, result: $0)
        })
    }
}

extension ClaimUsernamePresenter: ClaimUsernamePresenterProtocol {
    func setup() {
        provideViewModel()
        provideInputViewModel(shouldPrefill: true)
        validateUsername()
    }

    func update(from _: InputViewModelProtocol) {
        doUsernameCheckUpdateIfPossible()
    }

    func updateDigits(_ value: String) {
        let parsed = Int(value)
        selectedDigits = parsed

        if let parsed, availableDigits.contains(parsed) {
            digitsFieldState = .valid
        } else {
            digitsFieldState = .invalid
        }

        view?.didReceive(digitsState: digitsFieldState)
        validateUsername()
    }

    func resolveError() {
        switch usernameCheckResult {
        case .taken,
             .invalid:
            usernameCheckResult = nil
            resetDigitsState()
            provideInputViewModel(shouldPrefill: false)
            validateUsername()
        case .error:
            doUsernameCheckUpdateIfPossible()
        case .available,
             nil:
            break
        }
    }

    func confirm() {
        guard claimCancellable == nil else {
            return
        }

        guard
            let usernameViewModel,
            usernameViewModel.inputHandler.completed
        else {
            return
        }

        let username =
            if let selectedDigits {
                Username(name: partialNormalizedUsername, digits: selectedDigits)
            } else {
                Username(value: partialNormalizedUsername)
            }

        view?.userInteraction(enabled: false)
        view?.didStartLoading()
        claimCancellable = interactor.claim(username: username)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                switch completion {
                case .finished:
                    break
                case let .failure(error):
                    self?.didReceive(error: .claimFailed(error))
                }
            } receiveValue: { [weak self] in
                self?.didReceive(username: $0)
            }
    }

    func recover() {
        wireframe.showRecovery(from: view)
    }
}

extension ClaimUsernamePresenter: ClaimUsernameInteractorOutputProtocol {
    func didSaveUsername() {
        wireframe.finishFlow(from: view)
    }

    func authorizeUser(completion: @escaping AuthorizationCompletionBlock) {
        wireframe.authorize(animated: true, retriable: true, with: completion)
    }

    func didChangeAccountCreation(inProgress: Bool) {
        view?.setAccountCreationInProgress(inProgress)
        view?.userInteraction(enabled: !inProgress)
    }
}

private extension ClaimUsernamePresenter {
    func provideViewModel() {
        view?.didReceive(viewModel: viewModelProvider.viewModel())
    }

    func didReceive(username: Username) {
        logger.debug("Username: \(username)")
        interactor.save(username: username)
    }

    func didCompleteCheck(for username: Username, result: UsernameAvailableType) {
        logger.debug("Check result: \(result) for username: \(username.value)")

        view?.didStopLoading()

        guard
            partialNormalizedUsername == username.partialUsername
        else { return }

        usernameCheckResult = result

        switch result {
        case let .available(digits):
            availableDigits = digits
            if let first = digits.first {
                selectedDigits = first
                digitsFieldState = .valid

                let viewModel = InputViewModel.createDigitsInputViewModel(
                    initialValue: String(format: "%02d", first)
                )
                digitsViewModel = viewModel
                view?.didReceive(digitsInputViewModel: viewModel)
                view?.didReceive(digitsState: .valid)
            }
            validateUsername()
        case .taken,
             .invalid:
            validateUsername()
        case .error:
            view?.didReceiveValidation(
                result: .issue(
                    message: "",
                    context: UsernameValidationContext.usernameCheckFailed
                )
            )
        }
    }

    func didReceive(error: ClaimUsernameInteractorError) {
        logger.error("Error: \(error)")
        claimCancellable = nil
        view?.didStopLoading()
        view?.userInteraction(enabled: true)

        switch error {
        case .claimTimeout:
            break
        case let .claimFailed(remoteError):
            if !wireframe.present(error: remoteError, from: view) {
                wireframe.present(
                    message: String(localized: .claimUsernameActionError),
                    title: String(localized: .Common.error),
                    closeAction: String(localized: .Common.close),
                    from: view
                )
            }
        }
    }
}
