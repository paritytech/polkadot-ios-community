import UIKit
import PolkadotUI

extension ClaimUsernameViewLayout {
    enum Appearance {
        // Theme-driven via design system tokens (lite flow)
        case themed
        // Fixed pre-restyle look for the theme-locked full flow
        case fixed
    }

    func apply(appearance: Appearance) {
        switch appearance {
        case .themed:
            applyThemedAppearance()
        case .fixed:
            applyFixedAppearance()
        }
    }
}

private extension ClaimUsernameViewLayout {
    func applyThemedAppearance() {
        backgroundColor = .bgSurfaceMain

        headerLabel.textColor = .fgPrimary
        titleView.topLabel.textColor = .fgPrimary
        titleView.bottomLabel.textColor = .fgTertiary

        usernameWithDigitsView.theme = .default
    }

    func applyFixedAppearance() {
        backgroundColor = UIColor(.bgChatSurfaceMain)

        headerLabel.textColor = .textAndIconsPrimaryDark
        titleView.topLabel.textColor = .textAndIconsPrimaryDark
        titleView.bottomLabel.textColor = .textAndIconsTertiaryDark

        confirmView.issueView.applyBackgroundStyle(.fill12, cornerRadius: 12)

        usernameWithDigitsView.theme = .fullUsername

        applyFixedPlaceholderColor()
    }

    func applyFixedPlaceholderColor() {
        guard let placeholder = usernameInputView.textField.attributedPlaceholder?.string else {
            return
        }

        usernameInputView.textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.textAndIconsTertiaryDark]
        )
    }
}
