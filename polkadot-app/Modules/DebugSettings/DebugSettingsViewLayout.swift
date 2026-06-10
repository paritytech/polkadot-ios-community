import UIKit
import UIKit_iOS
import SnapKit
import PolkadotUI
import DesignSystem

final class DebugSettingsViewLayout: UIView {
    let clearBackupButton: RoundedButton = .create { button in
        button.applyMainStyle()
        button.changesContentOpacityWhenHighlighted = false
        button.setTitle("Clear Backup")
    }

    let clearReferralButton: RoundedButton = .create { button in
        button.applyMainStyle()
        button.changesContentOpacityWhenHighlighted = false
        button.setTitle("Clear Referral")
    }

    let shareLogsButton: RoundedButton = .create { button in
        button.applyMainStyle()
        button.imageWithTitleView?.title = "Share Logs"
    }

    let productsButton: RoundedButton = .create { button in
        button.applyMainStyle()
        button.imageWithTitleView?.title = "Products"
    }

    let dotNsBrowserButton: RoundedButton = .create { button in
        button.applyMainStyle()
        button.imageWithTitleView?.title = "Open SPA"
    }

    let simulateCrash: RoundedButton = .create { button in
        button.applyMainStyle()
        button.imageWithTitleView?.title = "Simulate Crash"
    }

    let clearJWTTokenButton: RoundedButton = .create { button in
        button.applyMainStyle()
        button.imageWithTitleView?.title = "Clear JWT Token"
    }

    let replaceEntropyButton: RoundedButton = .create { button in
        button.applyMainStyle()
        button.imageWithTitleView?.title = "Replace Entropy (Random)"
    }

    let themeSelectionButton: RoundedButton = .create { button in
        button.applyMainStyle()
        button.imageWithTitleView?.title = "Theme Selection"
    }

    let chainLabel: Label = .create { (view: Label) in
        view.typography = .bodyMedium
        view.textColor = .fgSecondary
        view.lineBreakMode = .byTruncatingMiddle
        view.text = "Chain ID: \(AppConfig.Chains.usernameChain)"
    }

    private let stackView: UIStackView = .create { stackView in
        stackView.axis = .vertical
        stackView.spacing = 8
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .bgSurfaceMain

        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
        }

        stackView.addArrangedSubviews([
            chainLabel,
            clearBackupButton,
            clearReferralButton,
            shareLogsButton,
            productsButton,
            dotNsBrowserButton,
            clearJWTTokenButton,
            simulateCrash,
            replaceEntropyButton,
            themeSelectionButton
        ])

        stackView.arrangedSubviews.forEach { button in
            button.snp.makeConstraints { make in
                make.height.equalTo(44)
            }
        }
    }

    func setupButtonEnabled(_ button: RoundedButton, isEnabled: Bool) {
        button.isUserInteractionEnabled = isEnabled

        if isEnabled {
            button.imageWithTitleView?.titleColor = .fgPrimaryInverted
        } else {
            button.imageWithTitleView?.titleColor = .black30
        }
    }
}
