import UIKit
import DesignSystem
import Foundation_iOS
import FoundationExt

class ClaimUsernameViewController: UIViewController, ViewHolder {
    typealias RootViewType = ClaimUsernameViewLayout

    let presenter: ClaimUsernamePresenterProtocol

    var keyboardHandler: KeyboardHandler?

    init(presenter: ClaimUsernamePresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = ClaimUsernameViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupLocalization()
        setupHandlers()

        presenter.setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if keyboardHandler == nil {
            setupKeyboardHandler()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        rootView.usernameInputView.textField.becomeFirstResponder()
    }

    private func setupHandlers() {
        rootView.usernameInputView.textField.addTarget(
            self,
            action: #selector(actionUsernameChanged),
            for: .editingChanged
        )

        rootView.usernameInputView.textField.addTarget(
            self,
            action: #selector(actionUsernameEditingDidBegin),
            for: .editingDidBegin
        )

        rootView.usernameInputView.textField.addTarget(
            self,
            action: #selector(actionUsernameEditingDidEnd),
            for: .editingDidEnd
        )

        rootView.digitsInputView.textField.addTarget(
            self,
            action: #selector(actionDigitsChanged),
            for: .editingChanged
        )

        rootView.digitsInputView.textField.addTarget(
            self,
            action: #selector(actionDigitsEditingDidBegin),
            for: .editingDidBegin
        )

        rootView.digitsInputView.textField.addTarget(
            self,
            action: #selector(actionDigitsEditingDidEnd),
            for: .editingDidEnd
        )

        rootView.confirmView.errorButton.addTarget(
            self,
            action: #selector(actionResolveError),
            for: .touchUpInside
        )

        rootView.confirmView.actionButton.addTarget(
            self,
            action: #selector(actionConfirm),
            for: .touchUpInside
        )

        rootView.recoveryControlView.addTarget(
            self,
            action: #selector(actionRecover),
            for: .touchUpInside
        )
    }

    private func setupLocalization() {
        let placeholder = NSAttributedString(
            string: String(localized: .claimUsernamePlaceholder),
            attributes: [.foregroundColor: UIColor.fgTertiary]
        )
        rootView.usernameInputView.textField.attributedPlaceholder = placeholder
    }

    private func apply(usernameContext: UsernameValidationContext?) {
        switch usernameContext {
        case .usernameTaken:
            rootView.apply(usernameAvailability: .taken)
            rootView.confirmView.bind(
                state: .errorAction(
                    String(localized: .Common.clear), nil
                )
            )
        case .usernameInvalid:
            rootView.apply(usernameAvailability: .invalid)
            rootView.confirmView.bind(
                state: .errorAction(
                    String(localized: .Common.clear), nil
                )
            )
        case .digitsInvalid:
            rootView.apply(usernameAvailability: .digitsTaken)
            rootView.confirmView.bind(state: .disabled)
        case .usernameCheckFailed:
            rootView.apply(usernameAvailability: nil)
            rootView.confirmView.bind(
                state: .errorAction(
                    String(localized: .Common.retry),
                    nil
                )
            )
        case nil:
            rootView.apply(usernameAvailability: nil)
        }
    }

    @objc
    func actionUsernameEditingDidBegin() {
        rootView.applyUsernameFocused(true)
    }

    @objc
    func actionUsernameEditingDidEnd() {
        rootView.applyUsernameFocused(false)
    }

    @objc
    func actionUsernameChanged() {
        if let viewModel = rootView.usernameInputView.inputViewModel {
            presenter.update(from: viewModel)
        }
    }

    @objc
    func actionDigitsChanged() {
        if let viewModel = rootView.digitsInputView.inputViewModel {
            presenter.updateDigits(viewModel.inputHandler.value)
        }
    }

    @objc
    func actionDigitsEditingDidBegin() {
        rootView.applyDigitsFocused(true)
    }

    @objc
    func actionDigitsEditingDidEnd() {
        rootView.applyDigitsFocused(false)
    }

    @objc
    func actionConfirm() {
        rootView.usernameInputView.textField.resignFirstResponder()

        presenter.confirm()
    }

    @objc
    func actionResolveError() {
        presenter.resolveError()
    }

    @objc
    func actionRecover() {
        presenter.recover()
    }

    func didReceiveValidation(result: ValidationResult) {
        guard !rootView.confirmView.isLoading else {
            return
        }

        switch result {
        case let .issue(title, context):
            rootView.confirmView.bind(state: .issue(title))
            apply(usernameContext: context as? UsernameValidationContext)
        case .valid:
            rootView.apply(usernameAvailability: .available)
            rootView.confirmView.bind(state: .confirm)
        }
    }
}

extension ClaimUsernameViewController: KeyboardAdoptable {}

extension ClaimUsernameViewController: ClaimUsernameViewProtocol {
    func didReceive(viewModel: ClaimUsernameViewLayout.ViewModel) {
        rootView.bind(viewModel: viewModel)
    }

    func didReceive(usernameInputViewModel: InputViewModelProtocol) {
        rootView.usernameInputView.bind(inputViewModel: usernameInputViewModel)
    }

    func didReceive(digitsInputViewModel: InputViewModelProtocol) {
        rootView.digitsInputView.bind(inputViewModel: digitsInputViewModel)
    }

    func didReceive(digitsState: DigitsFieldState) {
        rootView.apply(digitsState: digitsState)
    }

    func didStartLoading() {
        rootView.confirmView.bind(state: .loading)
    }

    func didStopLoading() {
        rootView.confirmView.bind(state: .confirm)
    }

    func userInteraction(enabled: Bool) {
        rootView.usernameInputView.isUserInteractionEnabled = enabled
    }

    func setAccountCreationInProgress(_ inProgress: Bool) {
        rootView.setAccountCreationInProgress(inProgress)
    }
}

final class ClaimLiteUsernameViewController: ClaimUsernameViewController {}

final class ClaimFullUsernameViewController: ClaimUsernameViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        traitOverrides.appTheme = ThemesRegistry.default
        rootView.apply(appearance: .fixed)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.traitOverrides.appTheme = ThemesRegistry.default
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.traitOverrides.remove(DSThemeTrait.self)
    }

    override func didReceiveValidation(result: ValidationResult) {
        super.didReceiveValidation(result: result)
        // Full username does not show the availability view if name is valid
        if result.isValid {
            rootView.usernameAvailabilityView.isHidden = true
        }

        if case .issue = result {
            // Full username flow shows the action name for the issue view
            rootView.confirmView.issueView.wrappedView.text = String(localized: .claimUsernameActionFull)
        }
    }
}

extension ClaimLiteUsernameViewController: HiddableBarWhenPushed {}
