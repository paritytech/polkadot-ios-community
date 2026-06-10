import UIKit
import Foundation_iOS
import PolkadotUI
import FoundationExt

final class UsernameWithDigitsView: GenericBackgroundView<UIView> {
    enum State {
        case normal
        case focused
        case error
        case success
    }

    struct Theme {
        struct Colors {
            let backgroundColor: UIColor
            let borderColor: UIColor
        }

        let normal: Colors
        let focused: Colors
        let error: Colors
        let success: Colors
        let usernameTextColor: UIColor
        let digitsTextColor: UIColor
        let tintColor: UIColor
        let separatorColor: UIColor
    }

    var theme: Theme = .default {
        didSet {
            applyTheme()
        }
    }

    private var currentState: State = .normal

    let usernameInputView: TextInputView = create {
        $0.textField.font = .titleLarge
        $0.roundedBackgroundView?.applyClear()
        $0.shouldUseClearButton = false
    }

    let digitsInputView: TextInputView = create {
        $0.textField.font = .titleLarge
        $0.textField.keyboardType = .numberPad
        $0.textField.textAlignment = .right
        $0.roundedBackgroundView?.applyClear()
        $0.shouldUseClearButton = false
    }

    private let separatorLine = UIView()

    private let digitsContainer: UIStackView = create {
        $0.axis = .horizontal
        $0.alignment = .center
        $0.spacing = 4
        $0.isHidden = true
    }

    var isDigitsVisible: Bool {
        !digitsContainer.isHidden
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        insets = UIEdgeInsets(horizontal: 16)

        setupLayout()
        applyTheme()
    }

    func apply(state: State) {
        currentState = state

        let colors =
            switch state {
            case .normal: theme.normal
            case .focused: theme.focused
            case .error: theme.error
            case .success: theme.success
            }

        applyBorderStyle(colors.borderColor, strokeWidth: 1, cornerRadius: 12)
        applyBackgroundStyle(colors.backgroundColor, cornerRadius: 12)
    }

    func setDigitsVisible(_ visible: Bool) {
        digitsContainer.isHidden = !visible
        if !visible {
            digitsInputView.textField.resignFirstResponder()
        }
    }
}

extension UsernameWithDigitsView.Theme {
    static let `default`: Self = .init(
        normal: .init(
            backgroundColor: .bgSurfaceContainer,
            borderColor: .strokePrimary
        ),
        focused: .init(
            backgroundColor: .bgSurfaceContainer,
            borderColor: .fgPrimary
        ),
        error: .init(
            backgroundColor: .bgStatusError.withAlphaComponent(0.12),
            borderColor: .strokeError
        ),
        success: .init(
            backgroundColor: .bgStatusSuccess.withAlphaComponent(0.12),
            borderColor: .strokeSuccess
        ),
        usernameTextColor: .fgPrimary,
        digitsTextColor: .fgSecondary,
        tintColor: .fgPrimary,
        separatorColor: .strokePrimary
    )

    static let fullUsername: Self = .init(
        normal: .init(
            backgroundColor: .white8,
            borderColor: .appliedStroke
        ),
        focused: .init(
            backgroundColor: .white8,
            borderColor: .appliedStroke
        ),
        error: .init(
            backgroundColor: .systemError.withAlphaComponent(0.12),
            borderColor: .systemError
        ),
        success: .init(
            backgroundColor: .systemSuccess.withAlphaComponent(0.12),
            borderColor: .systemSuccess
        ),
        usernameTextColor: .textAndIconsPrimaryDark,
        digitsTextColor: .textAndIconsSecondary,
        tintColor: .textAndIconsPrimaryDark,
        separatorColor: .appliedStroke
    )
}

// MARK: - Private functions

extension UsernameWithDigitsView {
    private func applyTheme() {
        usernameInputView.textField.textColor = theme.usernameTextColor
        usernameInputView.textField.tintColor = theme.tintColor

        digitsInputView.textField.textColor = theme.digitsTextColor
        digitsInputView.textField.tintColor = theme.tintColor

        separatorLine.backgroundColor = theme.separatorColor

        apply(state: currentState)
    }

    private func setupLayout() {
        digitsContainer.addArrangedSubview(separatorLine)
        digitsContainer.addArrangedSubview(digitsInputView)

        let contentStack = UIStackView(arrangedSubviews: [usernameInputView, digitsContainer])
        contentStack.axis = .horizontal
        contentStack.alignment = .fill
        contentStack.distribution = .fill

        usernameInputView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        digitsContainer.setContentHuggingPriority(.required, for: .horizontal)
        digitsContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

        separatorLine.snp.makeConstraints { make in
            make.width.equalTo(1)
            make.height.equalTo(32)
        }

        digitsInputView.snp.makeConstraints { make in
            make.width.equalTo(42)
        }

        wrappedView.addSubview(contentStack)
        contentStack.snp.makeConstraints { $0.edges.equalToSuperview() }
    }
}
