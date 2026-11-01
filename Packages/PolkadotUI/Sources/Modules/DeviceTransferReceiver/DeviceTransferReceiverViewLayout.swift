import SwiftUI
import DesignSystem

/// The new phone's transfer screens.
public struct DeviceTransferReceiverViewLayout: View {
    @State public var viewModel = DeviceTransferReceiverViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DSSpacings.large) {
                header
                texts
                details
            }
            .padding(.horizontal, DSSpacings.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let action {
                DSButton(
                    action.title,
                    style: action.style,
                    size: .largeIncreased,
                    expands: true,
                    action: action.handler
                )
                .padding(.horizontal, DSSpacings.mediumIncreased)
                .padding(.top, DSSpacings.small)
            }
        }
        .padding(.bottom, DSSpacings.mediumIncreased)
        .background(Color.bgSurfaceMain)
    }
}

private extension DeviceTransferReceiverViewLayout {
    @ViewBuilder
    var header: some View {
        switch viewModel.screen {
        case .reconnecting:
            statusIcon(.icon56WifiOff, color: .fgWarning)
        case .done:
            statusIcon(.icon20CheckCircle, color: .fgSuccess)
        case .declined,
             .cancelledOnOldPhone:
            statusIcon(.iconAlertCircle, color: .fgWarning)
        case .failed:
            statusIcon(.iconAlertCircle, color: .fgError)
        case .start,
             .waiting,
             .connecting,
             .syncing,
             .files,
             .finishing:
            DeviceTransferIllustration()
        }
    }

    var texts: some View {
        VStack(spacing: DSSpacings.large) {
            Text(title)
                .typography(.headlineMedium)
                .foregroundStyle(Color.fgPrimary)
            if let body = bodyText {
                Text(body)
                    .typography(.paragraphLarge)
                    .foregroundStyle(Color.fgSecondary)
            }
        }
        .multilineTextAlignment(.center)
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
            DeviceTransferProgressBar(label: nil, fraction: progress, detail: paused(at: progress))
        case .start,
             .done,
             .cancelledOnOldPhone,
             .failed:
            EmptyView()
        }
    }

    func statusIcon(_ resource: ImageResource, color: Color) -> some View {
        Image(resource)
            .resizable()
            .frame(width: 56, height: 56)
            .foregroundStyle(color)
    }

    @ViewBuilder
    func deviceCard(detail: KeyPath<DeviceTransferOldPhone, String>) -> some View {
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

    func paused(at progress: Double) -> String {
        String(localized: .deviceTransferProgressPaused(percent: Int((progress * 100).rounded())))
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

    var action: (title: String, style: DSButtonStyle.Style, handler: () -> Void)? {
        switch viewModel.screen {
        case .start:
            (String(localized: .deviceTransferReceiverActionTransfer), .primary, { viewModel.onStart?() })
        case .waiting,
             .connecting:
            (String(localized: .deviceTransferReceiverActionCancel), .ghost, { viewModel.onCancel?() })
        case .syncing,
             .files,
             .reconnecting:
            (String(localized: .deviceTransferReceiverActionCancelTransfer), .ghost, { viewModel.onCancel?() })
        case .done:
            (String(localized: .deviceTransferReceiverActionContinue), .primary, { viewModel.onContinue?() })
        case .declined:
            (String(localized: .deviceTransferReceiverActionSendNewRequest), .primary, { viewModel.onStart?() })
        case .cancelledOnOldPhone,
             .failed:
            (String(localized: .deviceTransferReceiverActionTryAgain), .primary, { viewModel.onStart?() })
        case .finishing:
            nil
        }
    }
}

private extension DeviceTransferOldPhone {
    var activeNow: String {
        String(localized: .deviceTransferDeviceActiveNow(operatingSystem: operatingSystem))
    }
}

private func receiverPreview(_ screen: DeviceTransferReceiverScreen) -> some View {
    let layout = DeviceTransferReceiverViewLayout()
    layout.viewModel.screen = screen
    layout.viewModel.oldPhone = DeviceTransferOldPhone(model: "iPhone 15", operatingSystem: "iOS 26.0")
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
