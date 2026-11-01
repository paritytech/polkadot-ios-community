import SwiftUI
import DesignSystem

/// The new phone's transfer screens.
public struct DeviceTransferReceiverViewLayout: View {
    @State public var viewModel = DeviceTransferReceiverViewModel()

    public init() {}

    public var body: some View {
        DeviceTransferScreen(
            title: title,
            message: bodyText,
            actions: actions,
            header: { header },
            details: { details }
        )
    }
}

private extension DeviceTransferReceiverViewLayout {
    @ViewBuilder
    var header: some View {
        switch viewModel.screen {
        case .reconnecting:
            DeviceTransferStatusIcon(resource: .icon56WifiOff, color: .fgWarning)
        case .done:
            DeviceTransferStatusIcon(resource: .icon20CheckCircle, color: .fgSuccess)
        case .declined,
             .cancelledOnOldPhone:
            DeviceTransferStatusIcon(resource: .iconAlertCircle, color: .fgWarning)
        case .failed:
            DeviceTransferStatusIcon(resource: .iconAlertCircle, color: .fgError)
        case .start,
             .waiting,
             .connecting,
             .syncing,
             .files,
             .finishing:
            DeviceTransferIllustration()
        }
    }

    @ViewBuilder
    var details: some View {
        switch viewModel.screen {
        case .waiting:
            deviceCard(detail: \.activeNow)
            DeviceTransferWaitingRow(text: String(localized: .deviceTransferWaitingOldPhone))
        case .connecting:
            deviceCard(detail: \.operatingSystem)
            DeviceTransferWaitingRow(text: String(localized: .deviceTransferWaitingSecureConnection))
        case .declined:
            deviceCard(detail: \.activeNow)
        case let .syncing(progress):
            DeviceTransferProgressBar(
                label: String(localized: .deviceTransferProgressData),
                fraction: progress,
                detail: nil
            )
        case let .files(progress, received, total):
            filesProgress(progress, detail: bytes(received, of: total))
        case .finishing:
            filesProgress(1, detail: nil)
        case let .reconnecting(progress):
            DeviceTransferProgressBar(label: nil, fraction: progress, detail: DeviceTransferText.paused(at: progress))
        case .start,
             .done,
             .cancelledOnOldPhone,
             .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    func deviceCard(detail: KeyPath<DeviceTransferPhone, String>) -> some View {
        if let oldPhone = viewModel.oldPhone {
            DeviceTransferDeviceCard(model: oldPhone.model, detail: oldPhone[keyPath: detail])
        }
    }

    func filesProgress(_ progress: Double, detail: String?) -> some View {
        VStack(spacing: DSSpacings.mediumIncreased) {
            DeviceTransferDoneRow(text: String(localized: .deviceTransferProgressData))
            DeviceTransferProgressBar(
                label: String(localized: .deviceTransferProgressFiles),
                fraction: progress,
                detail: detail
            )
        }
    }

    func bytes(_ received: UInt64, of total: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return String(localized: .deviceTransferProgressBytes(
            received: formatter.string(fromByteCount: Int64(clamping: received)),
            total: formatter.string(fromByteCount: Int64(clamping: total))
        ))
    }
}

private extension DeviceTransferReceiverViewLayout {
    var title: String {
        switch viewModel.screen {
        case .start: String(localized: .deviceTransferReceiverTitleStart)
        case .waiting: String(localized: .deviceTransferReceiverTitleWaiting)
        case .connecting: String(localized: .deviceTransferReceiverTitleConnecting)
        case .syncing,
             .files: String(localized: .deviceTransferReceiverTitleTransferring)
        case .reconnecting: String(localized: .deviceTransferReceiverTitleConnectionLost)
        case .finishing: String(localized: .deviceTransferReceiverTitleFinishing)
        case .done: String(localized: .deviceTransferReceiverTitleDone)
        case .declined: String(localized: .deviceTransferReceiverTitleDeclined)
        case .cancelledOnOldPhone: String(localized: .deviceTransferReceiverTitleCancelled)
        case .failed: String(localized: .deviceTransferReceiverTitleFailed)
        }
    }

    var bodyText: String? {
        switch viewModel.screen {
        case .start: String(localized: .deviceTransferReceiverBodyStart)
        case .waiting: String(localized: .deviceTransferReceiverBodyWaiting)
        case .syncing,
             .files,
             .finishing: String(localized: .deviceTransferReceiverBodyTransferring)
        case .reconnecting: String(localized: .deviceTransferReceiverBodyConnectionLost)
        case .done: String(localized: .deviceTransferReceiverBodyDone)
        case .declined: String(localized: .deviceTransferReceiverBodyDeclined)
        case .cancelledOnOldPhone: String(localized: .deviceTransferReceiverBodyCancelled)
        case .failed: String(localized: .deviceTransferReceiverBodyFailed)
        case .connecting: nil
        }
    }

    var actions: [DeviceTransferAction] {
        switch viewModel.screen {
        case .start:
            [DeviceTransferAction(.deviceTransferReceiverActionTransfer, .primary) { viewModel.onStart?() }]
        case .waiting:
            activationActions(style: .secondary) + [
                DeviceTransferAction(.deviceTransferReceiverActionCancel, .ghost) { viewModel.onCancel?() }
            ]
        case .connecting:
            [DeviceTransferAction(.deviceTransferReceiverActionCancel, .ghost) { viewModel.onCancel?() }]
        case .syncing,
             .files,
             .reconnecting:
            [DeviceTransferAction(.deviceTransferReceiverActionCancelTransfer, .ghost) { viewModel.onCancel?() }]
        case .done:
            [DeviceTransferAction(.deviceTransferReceiverActionContinue, .primary) { viewModel.onContinue?() }]
        case .declined:
            [DeviceTransferAction(.deviceTransferReceiverActionSendNewRequest, .primary) { viewModel.onStart?() }]
                + activationActions(style: .ghost)
        case .cancelledOnOldPhone,
             .failed:
            [DeviceTransferAction(.deviceTransferReceiverActionTryAgain, .primary) { viewModel.onStart?() }]
                + activationActions(style: .ghost)
        case .finishing:
            []
        }
    }

    func activationActions(style: DSButtonStyle.Style) -> [DeviceTransferAction] {
        guard viewModel.offersActivation else { return [] }
        return [DeviceTransferAction(.deviceTransferReceiverActionNoAccess, style) { viewModel.onActivate?() }]
    }
}

private extension DeviceTransferPhone {
    var activeNow: String {
        String(localized: .deviceTransferDeviceActiveNow(operatingSystem: operatingSystem))
    }
}

private func receiverPreview(_ screen: DeviceTransferReceiverScreen) -> some View {
    let layout = DeviceTransferReceiverViewLayout()
    layout.viewModel.screen = screen
    layout.viewModel.oldPhone = DeviceTransferPhone(model: "iPhone 15", operatingSystem: "iOS 26.0")
    layout.viewModel.offersActivation = true
    return ThemeSwitchingPreview { layout }
}

#Preview("Ready to transfer") {
    receiverPreview(.start)
}

#Preview("Waiting for the old phone") {
    receiverPreview(.waiting)
}

#Preview("Connecting") {
    receiverPreview(.connecting)
}

#Preview("Transferring data") {
    receiverPreview(.syncing(progress: 0.1))
}

#Preview("Transferring files") {
    receiverPreview(.files(progress: 0.64, receivedBytes: 1_200_000_000, totalBytes: 1_900_000_000))
}

#Preview("Connection lost") {
    receiverPreview(.reconnecting(progress: 0.64))
}

#Preview("Finishing up") {
    receiverPreview(.finishing)
}

#Preview("Transfer complete") {
    receiverPreview(.done)
}

#Preview("Declined on the old phone") {
    receiverPreview(.declined)
}

#Preview("Cancelled on the old phone") {
    receiverPreview(.cancelledOnOldPhone)
}

#Preview("Transfer failed") {
    receiverPreview(.failed)
}
