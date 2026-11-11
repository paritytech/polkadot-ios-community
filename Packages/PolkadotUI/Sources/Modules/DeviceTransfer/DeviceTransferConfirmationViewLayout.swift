import DesignSystem
import UIKit
internal import UIKit_iOS
internal import SnapKit

/// Figma "Bottom sheet base" for transfer confirmations: a warning, what follows, and a destructive confirm.
/// Without a confirm title the sheet only informs, and dismiss is its one action.
public final class DeviceTransferConfirmationViewLayout: BottomSheetBaseLayout {
    public struct ViewModel {
        let title: String
        let message: String
        let points: [String]
        let confirmTitle: String?
        let dismissTitle: String

        public init(title: String, message: String, points: [String], confirmTitle: String?, dismissTitle: String) {
            self.title = title
            self.message = message
            self.points = points
            self.confirmTitle = confirmTitle
            self.dismissTitle = dismissTitle
        }
    }

    private let iconView: UIImageView = .create {
        $0.image = UIImage(resource: .iconAlertCircle).withRenderingMode(.alwaysTemplate)
        $0.tintColor = .fgWarning
        $0.contentMode = .scaleAspectFit
    }

    private let titleLabel: Label = create {
        $0.typography = .headlineSmall
        $0.textColor = .fgPrimary
        $0.numberOfLines = 0
    }

    private let messageLabel: Label = create {
        $0.typography = .paragraphLarge
        $0.textColor = .fgPrimary
        $0.numberOfLines = 0
    }

    private let pointsView: UIStackView = .create {
        $0.axis = .vertical
        $0.spacing = DSSpacings.extraMedium
    }

    private let buttonsView: GenericPairValueView<DSButtonView, DSButtonView> = .create { view in
        view.fView.style = .destructive
        view.fView.expands = true
        view.sView.style = .tertiary
        view.sView.expands = true
        view.setVerticalAndSpacing(DSSpacings.mediumIncreased)
    }

    public var confirmButton: DSButtonView {
        buttonsView.fView
    }

    public var dismissButton: DSButtonView {
        buttonsView.sView
    }

    override public func setupLayout() {
        super.setupLayout()

        let iconSlot = UIView()
        iconSlot.addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.size.equalTo(56)
        }

        let contentStack = UIStackView(arrangedSubviews: [iconSlot, titleLabel, messageLabel, pointsView, buttonsView])
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = DSSpacings.small
        contentStack.setCustomSpacing(DSSpacings.mediumIncreased, after: iconSlot)
        contentStack.setCustomSpacing(DSSpacings.large, after: messageLabel)
        contentStack.setCustomSpacing(DSSpacings.large, after: pointsView)

        contentView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    public func bind(viewModel: ViewModel) {
        titleLabel.text = viewModel.title
        messageLabel.text = viewModel.message
        confirmButton.setTitle(viewModel.confirmTitle ?? "")
        confirmButton.isHidden = viewModel.confirmTitle == nil
        dismissButton.setTitle(viewModel.dismissTitle)

        pointsView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        viewModel.points.forEach { pointsView.addArrangedSubview(makePointRow($0)) }
        pointsView.isHidden = viewModel.points.isEmpty
    }
}

private extension DeviceTransferConfirmationViewLayout {
    func makePointRow(_ text: String) -> UIView {
        let bullet = UIView()
        bullet.backgroundColor = .fgSecondary
        bullet.layer.cornerRadius = 3

        let label = Label()
        label.typography = .bodyMedium
        label.textColor = .fgSecondary
        label.numberOfLines = 0
        label.text = text

        let row = UIView()
        row.addSubview(bullet)
        row.addSubview(label)

        bullet.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.size.equalTo(6)
            make.centerY.equalTo(label.snp.firstBaseline).offset(-4)
        }
        label.snp.makeConstraints { make in
            make.leading.equalTo(bullet.snp.trailing).offset(DSSpacings.extraMedium)
            make.top.bottom.trailing.equalToSuperview()
        }

        return row
    }
}

public extension DeviceTransferConfirmationViewLayout.ViewModel {
    static var activateWithoutTransfer: Self {
        Self(
            title: String(localized: .deviceTransferActivateTitle),
            message: String(localized: .deviceTransferActivateBody),
            points: [
                String(localized: .deviceTransferActivatePointData),
                String(localized: .deviceTransferActivatePointOldPhone),
                String(localized: .deviceTransferActivatePointLater)
            ],
            confirmTitle: String(localized: .deviceTransferActivateAction),
            dismissTitle: String(localized: .deviceTransferReceiverActionCancel)
        )
    }

    /// The old phone can't hand over while it's still claiming or minting payments: only it can finish them.
    static func pendingPayments(receiving: Int, sending: Int) -> Self {
        let parts = [
            receiving > 0 ? String(localized: .deviceTransferPendingReceiving(receiving)) : nil,
            sending > 0 ? String(localized: .deviceTransferPendingSending(sending)) : nil
        ].compactMap { $0 }
        let message = parts.count == 2
            ? String(localized: .deviceTransferPendingBodyBoth(parts[0], parts[1]))
            : String(localized: .deviceTransferPendingBodyOne(parts.first ?? ""))

        return Self(
            title: String(localized: .deviceTransferPendingTitle),
            message: message,
            points: [],
            confirmTitle: nil,
            dismissTitle: String(localized: .deviceTransferReceiverActionCancel)
        )
    }

    static var cancelReceivingTransfer: Self {
        cancelTransfer(message: String(localized: .deviceTransferCancelBody))
    }

    static var cancelSendingTransfer: Self {
        cancelTransfer(message: String(localized: .deviceTransferCancelSenderBody))
    }

    private static func cancelTransfer(message: String) -> Self {
        Self(
            title: String(localized: .deviceTransferCancelTitle),
            message: message,
            points: [],
            confirmTitle: String(localized: .deviceTransferReceiverActionCancelTransfer),
            dismissTitle: String(localized: .deviceTransferCancelKeep)
        )
    }
}
