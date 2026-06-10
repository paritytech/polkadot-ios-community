import Observation
import SwiftUI
import PolkadotUI

@Observable
final class Web3SummitSpaOverlayModel {
    var attendanceStatus: Web3SummitAttendanceStatus = .notCheckedIn
    var isSkippable: Bool = false
}

struct Web3SummitSpaOverlay: View {
    let model: Web3SummitSpaOverlayModel
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if model.isSkippable {
                button(
                    title: String(localized: .web3SummitDebugSkip),
                    style: .mainDark,
                    action: onSkip
                )
            }

            switch model.attendanceStatus {
            case .notCheckedIn:
                EmptyView()
            case .checkedIn:
                finishingRegistrationButton
            case .confirmed:
                startButton
            }
        }
        .padding(16)
    }

    private var startButton: some View {
        Button(action: onStart) {
            Text(String(localized: .web3SummitStartUsingApp))
                .typography(.titleMedium)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.mainWhite)
    }

    private var finishingRegistrationButton: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.fgPrimaryInverted)
                Text(String(localized: .web3SummitFinishingRegistration))
                    .typography(.titleMedium)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.mainWhite)
        .disabled(true)
    }

    private func button(
        title: String,
        style: MainButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .typography(.titleMedium)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(style)
    }
}
