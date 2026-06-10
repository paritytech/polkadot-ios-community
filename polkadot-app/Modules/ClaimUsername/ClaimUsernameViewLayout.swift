import UIKit
import PolkadotUI
import FoundationExt

final class ClaimUsernameViewLayout: UIView {
    let contentView: UIView = create {
        $0.backgroundColor = .clear
    }

    let headerLabel: Label = create {
        $0.typography = .titleLarge
        $0.numberOfLines = 0
        $0.textAlignment = .center
    }

    let titleView: TopBottomLabelView = .create { view in
        view.topLabel.typography = .headlineLarge
        view.topLabel.textAlignment = .center
        view.topLabel.numberOfLines = 0

        view.bottomLabel.typography = .paragraphLarge
        view.bottomLabel.textAlignment = .center
        view.bottomLabel.numberOfLines = 0

        view.spacing = 12
    }

    var titleLabel: UILabel {
        titleView.topLabel
    }

    var detailsLabel: UILabel {
        titleView.bottomLabel
    }

    let usernameWithDigitsView = UsernameWithDigitsView()

    private var isUsernameFocused = false
    private var isDigitsFocused = false
    private var currentDigitsState: DigitsFieldState = .hidden
    private var currentAvailability: UsernameAvailabilityView.ViewModel?

    var usernameInputView: TextInputView {
        usernameWithDigitsView.usernameInputView
    }

    var digitsInputView: TextInputView {
        usernameWithDigitsView.digitsInputView
    }

    var usernameAvailabilityView: UsernameAvailabilityView = .create { view in
        view.isHidden = true
    }

    let actionsContainer: UIStackView = create {
        $0.axis = .vertical
        $0.spacing = 16
    }

    let confirmView: ConfirmView = .create { view in
        view.bind(state: .confirm)
    }

    let activityIndicatorView: ActivityIndicatorView = create {
        $0.alpha = 0
    }

    let recoveryControlView: ControlView<UIView, Label> = create {
        $0.changesContentOpacityWhenHighlighted = true
    }

    let termsOfUserTextView: UITextView = .create {
        $0.isEditable = false
        $0.isSelectable = true
        $0.isScrollEnabled = false
        $0.backgroundColor = .clear
        $0.textContainerInset = .zero
        $0.linkTextAttributes = LabelStyle.body14Regular()
            .attributes(for: .center, textColor: UIColor.fgPrimary)
    }

    private var recoveryLabel: Label {
        recoveryControlView.controlContentView
    }

    private var recoveryCollapsedConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupUsernameInputView()
        setupLayout()
        setupAccessibilityIdentifiers()
        apply(appearance: .themed)
    }

    func applyUsernameFocused(_ focused: Bool) {
        isUsernameFocused = focused
        refreshUsernameViewState()
    }

    func applyDigitsFocused(_ focused: Bool) {
        isDigitsFocused = focused
        refreshUsernameViewState()
    }

    func apply(digitsState: DigitsFieldState) {
        currentDigitsState = digitsState
        usernameWithDigitsView.setDigitsVisible(digitsState != .hidden)
        refreshUsernameViewState()
    }

    func apply(usernameAvailability: UsernameAvailabilityView.ViewModel?) {
        currentAvailability = usernameAvailability

        if let usernameAvailability {
            usernameAvailabilityView.isHidden = false
            usernameAvailabilityView.bind(viewModel: usernameAvailability)
        } else {
            usernameAvailabilityView.isHidden = true
        }

        refreshUsernameViewState()
    }

    private func refreshUsernameViewState() {
        if currentDigitsState == .invalid {
            usernameWithDigitsView.apply(state: .error)
            return
        }

        switch currentAvailability {
        case .available:
            usernameWithDigitsView.apply(state: .success)
        case .taken,
             .invalid,
             .digitsTaken:
            usernameWithDigitsView.apply(state: .error)
        case .none:
            let anyFocused = isUsernameFocused || isDigitsFocused
            usernameWithDigitsView.apply(state: anyFocused ? .focused : .normal)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUsernameInputView() {
        usernameInputView.textField.textContentType = .nickname
        usernameInputView.textField.autocorrectionType = .no
        usernameInputView.textField.spellCheckingType = .no
        usernameInputView.textField.smartQuotesType = .no
        usernameInputView.textField.smartDashesType = .no
        usernameInputView.textField.smartInsertDeleteType = .no
    }

    private func setupLayout() {
        setupActivityIndicatorViewLayout()
        setupContentViewLayout()
    }

    private func setupContentViewLayout() {
        actionsContainer.addArrangedSubview(recoveryControlView)
        actionsContainer.addArrangedSubview(confirmView)
        actionsContainer.addArrangedSubview(termsOfUserTextView)

        addSubview(contentView)
        contentView.snp.makeConstraints {
            $0.directionalEdges.equalToSuperview()
        }

        contentView.addSubview(headerLabel)
        headerLabel.snp.makeConstraints {
            $0.directionalHorizontalEdges.equalToSuperview().inset(16)
            $0.top.equalTo(safeAreaLayoutGuide.snp.top).offset(11)
        }

        contentView.addSubview(titleView)
        titleView.snp.makeConstraints { make in
            make.top.equalTo(headerLabel.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetExtraWide)
        }

        contentView.addSubview(usernameWithDigitsView)
        usernameWithDigitsView.snp.makeConstraints { make in
            make.top.equalTo(titleView.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetWide)
            make.height.equalTo(56)
        }

        contentView.addSubview(usernameAvailabilityView)
        usernameAvailabilityView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(usernameWithDigitsView.snp.bottom).offset(24)
        }

        contentView.addSubview(actionsContainer)
        actionsContainer.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetWide)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-17)
        }

        confirmView.snp.makeConstraints { make in
            make.height.equalTo(UIConstants.actionHeight)
        }
    }

    private func setupActivityIndicatorViewLayout() {
        addSubview(activityIndicatorView)
        activityIndicatorView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(32)
            $0.centerY.equalToSuperview()
        }
    }

    private func setupAccessibilityIdentifiers() {
        usernameInputView.accessibilityIdentifier = "username_input"
        digitsInputView.accessibilityIdentifier = "digits_input"
        confirmView.accessibilityIdentifier = "username_submit_button"
        recoveryLabel.accessibilityIdentifier = "onboarding_recover_here"
    }
}

// MARK: - KeyboardAdoptableViewLayout

extension ClaimUsernameViewLayout: KeyboardAdoptableViewLayout {
    func adoptToVisibleKeyboard(bottomInset: CGFloat) {
        actionsContainer.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetWide)
            make.bottom.equalToSuperview().inset(bottomInset + 24)
        }
    }

    func adoptToHiddenKeyboard() {
        actionsContainer.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetWide)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-24)
        }
    }
}

extension ClaimUsernameViewLayout {
    struct ViewModel {
        let headerText: String
        let title: String
        let details: String
        let actionTitle: String
        let recoveryActionString: NSAttributedString?
        let termsActionString: NSAttributedString?
    }

    func bind(viewModel: ViewModel) {
        headerLabel.text = viewModel.headerText
        titleLabel.text = viewModel.title
        detailsLabel.text = viewModel.details
        confirmView.actionButton.setTitle(viewModel.actionTitle)

        if let recoveryActionString = viewModel.recoveryActionString {
            recoveryLabel.attributedText = recoveryActionString
            recoveryControlView.isHidden = false
        } else {
            recoveryControlView.isHidden = true
        }

        if let termsActionString = viewModel.termsActionString {
            termsOfUserTextView.attributedText = termsActionString
            termsOfUserTextView.isHidden = false
        } else {
            termsOfUserTextView.isHidden = true
        }
    }

    func setAccountCreationInProgress(_ inProgress: Bool) {
        if inProgress {
            activityIndicatorView.text = String(localized: .creatingAccountDescription)
            activityIndicatorView.startAnimating()
            usernameInputView.textField.resignFirstResponder()
        } else {
            activityIndicatorView.stopAnimating()
        }

        UIView.animate(withDuration: 0.25) { [self] in
            activityIndicatorView.alpha = inProgress ? 1 : 0
            contentView.alpha = inProgress ? 0 : 1
        }
    }
}

struct Terms {
    let termsUrl: URL
    let privacyPolicyUrl: URL
}
