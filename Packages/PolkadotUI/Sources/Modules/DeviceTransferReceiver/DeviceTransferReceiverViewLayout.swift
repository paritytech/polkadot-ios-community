import SwiftUI
import DesignSystem

/// Titles and actions only; the Figma layout replaces the body.
public struct DeviceTransferReceiverViewLayout: View {
    @State public var viewModel = DeviceTransferReceiverViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(title)
                .typography(.titleLarge)
                .foregroundStyle(Color.fgPrimary)
                .multilineTextAlignment(.center)
            Spacer()
            if let action {
                Button(action.title, action: action.handler)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(Color.bgSurfaceMain)
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

    var action: (title: String, handler: () -> Void)? {
        switch viewModel.screen {
        case .start:
            (String(localized: .deviceTransferReceiverActionTransfer), { viewModel.onStart?() })
        case .waiting,
             .connecting:
            (String(localized: .deviceTransferReceiverActionCancel), { viewModel.onCancel?() })
        case .syncing,
             .files,
             .reconnecting:
            (String(localized: .deviceTransferReceiverActionCancelTransfer), { viewModel.onCancel?() })
        case .done:
            (String(localized: .deviceTransferReceiverActionContinue), { viewModel.onContinue?() })
        case .declined:
            (String(localized: .deviceTransferReceiverActionSendNewRequest), { viewModel.onStart?() })
        case .cancelledOnOldPhone,
             .failed:
            (String(localized: .deviceTransferReceiverActionTryAgain), { viewModel.onStart?() })
        case .finishing:
            nil
        }
    }
}

#Preview {
    DeviceTransferReceiverViewLayout()
}
