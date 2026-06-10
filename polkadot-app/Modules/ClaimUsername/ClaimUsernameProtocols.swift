import Foundation_iOS
import Combine
import UIKitExt

protocol ClaimUsernameViewProtocol: ControllerValidationResultPresentable {
    func didReceive(viewModel: ClaimUsernameViewLayout.ViewModel)
    func didReceive(usernameInputViewModel: InputViewModelProtocol)
    func didReceive(digitsInputViewModel: InputViewModelProtocol)
    func didReceive(digitsState: DigitsFieldState)
    func didStartLoading()
    func didStopLoading()
    func userInteraction(enabled: Bool)
    func setAccountCreationInProgress(_ inProgress: Bool)
}

protocol ClaimUsernamePresenterProtocol: AnyObject {
    func setup()
    func update(from viewModel: InputViewModelProtocol)
    func updateDigits(_ value: String)
    func resolveError()
    func confirm()
    func recover()
}

protocol ClaimUsernameInteractorInputProtocol: AnyObject {
    var metadata: UsernameMetadata { get }

    func check(username: Username) -> AnyPublisher<UsernameAvailableType, any Error>
    func claim(username: Username) -> AnyPublisher<Username, Error>
    func save(username: Username)
}

protocol ClaimUsernameInteractorOutputProtocol: AnyObject {
    func didSaveUsername()
    func authorizeUser(completion: @escaping AuthorizationCompletionBlock)
    func didChangeAccountCreation(inProgress: Bool)
}

protocol ClaimUsernameWireframeProtocol:
    AlertPresentable,
    UsernameValidationErrorPresentable,
    AuthorizationPresentable,
    ErrorPresentable {
    func finishFlow(from view: ControllerBackedProtocol?)
    func showRecovery(from view: ControllerBackedProtocol?)
}
