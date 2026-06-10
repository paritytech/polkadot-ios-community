import Foundation
import PolkadotUI
import FoundationExt

protocol ClaimUsernameViewModelProviding {
    func viewModel() -> ClaimUsernameViewLayout.ViewModel
}

final class ClaimUsernameViewModelFactory {
    let recoverable: Bool
    let full: Bool

    init(recoverable: Bool, full: Bool) {
        self.recoverable = recoverable
        self.full = full
    }
}

extension ClaimUsernameViewModelFactory: ClaimUsernameViewModelProviding {
    func viewModel() -> ClaimUsernameViewLayout.ViewModel {
        if full {
            fullViewModel()
        } else if recoverable {
            recoverableViewModel()
        } else {
            recoveredViewModel()
        }
    }
}

private extension ClaimUsernameViewModelFactory {
    func recoveredViewModel() -> ClaimUsernameViewLayout.ViewModel {
        ClaimUsernameViewLayout.ViewModel(
            headerText: String(localized: .claimUsernameHeaderTitleRecovered),
            title: String(localized: .claimUsernameTitle),
            details: String(localized: .claimUsernameDetailsRecovered),
            actionTitle: String(localized: .claimUsernameAction),
            recoveryActionString: nil,
            termsActionString: nil
        )
    }

    func recoverableViewModel() -> ClaimUsernameViewLayout.ViewModel {
        let defaultAttributes = LabelStyle.body14Regular().attributes(
            for: .center,
            textColor: .fgTertiary
        )
        let highlightingAttributes = LabelStyle.body14Regular().attributes(
            for: .center,
            textColor: .fgPrimary
        )

        let string = NSAttributedString.highlightedItems(
            [
                String(localized: .claimUsernameRecoverHere)
            ],
            formattingClosure: { items in
                String(localized: .claimUsernameRecoverAction(highlightedItem: items[0]))
            },
            highlightingAttributes: highlightingAttributes,
            defaultAttributes: defaultAttributes
        )

        let terms = NSAttributedString.highlightedItems(
            [
                String(localized: .claimUsernameTermsText),
                String(localized: .claimUsernamePrivacyText)
            ],
            formattingClosure: { items in
                String(localized: .claimUsernameTermsOfUseAndPrivacyPolicy(items[0], items[1]))
            },
            highlightingAttributes: [:],
            defaultAttributes: defaultAttributes,
            customAttributes: [
                0: [.link: AppConfig.termsOfUseLink],
                1: [.link: AppConfig.privacyPolicyLink]
            ]
        )

        return ClaimUsernameViewLayout.ViewModel(
            headerText: String(localized: .claimUsernameHeaderTitle),
            title: String(localized: .claimUsernameTitle),
            details: String(localized: .claimUsernameDetails),
            actionTitle: String(localized: .claimUsernameAction),
            recoveryActionString: string,
            termsActionString: terms
        )
    }

    func fullViewModel() -> ClaimUsernameViewLayout.ViewModel {
        ClaimUsernameViewLayout.ViewModel(
            headerText: "",
            title: String(localized: .claimUsernameTitleFull),
            details: String(localized: .claimUsernameDetailsFull),
            actionTitle: String(localized: .claimUsernameActionFull),
            recoveryActionString: nil,
            termsActionString: nil
        )
    }
}
