import SwiftUI
import DesignSystem

/// The old phone's transfer screens.
public struct DeviceTransferSenderViewLayout: View {
    @State public var viewModel = DeviceTransferSenderViewModel()

    public init() {}

    public var body: some View {
        DeviceTransferScreen(
            title: title,
            message: message,
            actions: actions,
            header: { header },
            details: { details }
        )
    }
}

private extension DeviceTransferSenderViewLayout {
    var model: String {
        viewModel.newPhone?.model ?? ""
    }

    @ViewBuilder
    var header: some View {
        switch viewModel.screen {
        case .reconnecting:
            DeviceTransferStatusIcon(resource: .icon56WifiOff, color: .fgWarning)
        case .cancelledOnNewPhone:
            DeviceTransferStatusIcon(resource: .iconAlertCircle, color: .fgWarning)
        case .connecting,
             .sendingData,
             .sendingFiles,
             .finishing:
            DeviceTransferIllustration()
        }
    }

    @ViewBuilder
    var details: some View {
        switch viewModel.screen {
        case .connecting:
            if let newPhone = viewModel.newPhone {
                DeviceTransferDeviceCard(model: newPhone.model, detail: newPhone.operatingSystem)
            }
            DeviceTransferWaitingRow(text: String(localized: .deviceTransferWaitingSecureConnection))
        case let .sendingData(progress):
            dataProgress(progress, detail: nil)
        case .sendingFiles:
            dataDone(then: String(localized: .deviceTransferSenderFiles))
        case let .reconnecting(progress?):
            dataProgress(progress, detail: DeviceTransferText.paused(at: progress))
        case .reconnecting:
            DeviceTransferDoneRow(text: String(localized: .deviceTransferProgressData))
        case .finishing:
            dataDone(then: String(localized: .deviceTransferSenderWaitingNewPhone(model: model)))
        case .cancelledOnNewPhone:
            EmptyView()
        }
    }

    func dataProgress(_ progress: Double, detail: String?) -> some View {
        DeviceTransferProgressBar(
            label: String(localized: .deviceTransferProgressData),
            fraction: progress,
            detail: detail
        )
    }

    func dataDone(then waiting: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacings.mediumIncreased) {
            DeviceTransferDoneRow(text: String(localized: .deviceTransferProgressData))
            DeviceTransferWaitingRow(text: waiting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension DeviceTransferSenderViewLayout {
    var title: String {
        switch viewModel.screen {
        case .connecting: String(localized: .deviceTransferSenderTitleConnecting)
        case .sendingData,
             .sendingFiles: String(localized: .deviceTransferSenderTitleSending)
        case .reconnecting: String(localized: .deviceTransferReceiverTitleConnectionLost)
        case .finishing: String(localized: .deviceTransferReceiverTitleFinishing)
        case .cancelledOnNewPhone: String(localized: .deviceTransferReceiverTitleCancelled)
        }
    }

    var message: String? {
        switch viewModel.screen {
        case .sendingData,
             .sendingFiles: String(localized: .deviceTransferSenderBodySending(model: model))
        case .reconnecting: String(localized: .deviceTransferSenderBodyConnectionLost(model: model))
        case .cancelledOnNewPhone: String(localized: .deviceTransferSenderBodyCancelled(model: model))
        case .connecting,
             .finishing: nil
        }
    }

    var actions: [DeviceTransferAction] {
        switch viewModel.screen {
        case .connecting:
            [DeviceTransferAction(.deviceTransferReceiverActionCancel, .ghost) { viewModel.onCancel?() }]
        case .sendingData,
             .sendingFiles,
             .reconnecting:
            [DeviceTransferAction(.deviceTransferReceiverActionCancelTransfer, .ghost) { viewModel.onCancel?() }]
        case .cancelledOnNewPhone:
            [DeviceTransferAction(.deviceTransferSenderActionBackToChats, .primary) { viewModel.onBackToChats?() }]
        case .finishing:
            []
        }
    }
}

private func senderPreview(_ screen: DeviceTransferSenderScreen) -> some View {
    let layout = DeviceTransferSenderViewLayout()
    layout.viewModel.screen = screen
    layout.viewModel.newPhone = DeviceTransferPhone(model: "iPhone 17 Pro", operatingSystem: "iOS 26.1")
    return ThemeSwitchingPreview { layout }
}

#Preview("Connecting") {
    senderPreview(.connecting)
}

#Preview("Sending data") {
    senderPreview(.sendingData(progress: 0.42))
}

#Preview("Sending files") {
    senderPreview(.sendingFiles)
}

#Preview("Connection lost while sending data") {
    senderPreview(.reconnecting(progress: 0.42))
}

#Preview("Connection lost while sending files") {
    senderPreview(.reconnecting(progress: nil))
}

#Preview("Finishing up") {
    senderPreview(.finishing)
}

#Preview("Cancelled on the new phone") {
    senderPreview(.cancelledOnNewPhone)
}
