import UIKit
import PolkadotUI

final class UsernameAvailabilityView: GenericBackgroundView<Label> {
    var titleLabel: Label {
        wrappedView
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 26)
    }

    func bind(viewModel: ViewModel) {
        let text =
            switch viewModel {
            case .available: String(localized: .claimUsernameIsAvailable)
            case .taken: String(localized: .claimUsernameIsTaken)
            case .invalid: String(localized: .claimUsernameIsInvalid)
            case .digitsTaken: String(localized: .claimUsernameDigitsTaken)
            }

        let isSuccess = viewModel == .available
        let statusColor: UIColor = isSuccess ? .bgStatusSuccess : .bgStatusError

        applyBackgroundStyle(statusColor.withAlphaComponent(0.12), cornerRadius: 8)
        titleLabel.textColor = isSuccess ? .fgSuccess : .fgError
        titleLabel.text = text
    }

    override func configure() {
        super.configure()

        insets = UIEdgeInsets(horizontal: 8, vertical: 4)

        titleLabel.typography = .paragraphSmall
    }
}

extension UsernameAvailabilityView {
    enum ViewModel {
        case available
        case taken
        case invalid
        case digitsTaken
    }
}
