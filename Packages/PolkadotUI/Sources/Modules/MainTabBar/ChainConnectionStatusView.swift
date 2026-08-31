import SwiftUI
import DesignSystem

public enum ChainConnectionState: Hashable {
    case connected
    case connecting
    case offline
}

public struct ChainConnectionStatusViewModel: Hashable, Identifiable {
    public let id: String
    public let title: String
    public let state: ChainConnectionState
    public let stateTitle: String
    public let latencyText: String?

    public init(
        id: String,
        title: String,
        state: ChainConnectionState,
        stateTitle: String,
        latencyText: String?
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.stateTitle = stateTitle
        self.latencyText = latencyText
    }
}

public struct ChainConnectionStatusView: View, Hashable {
    public let rows: [ChainConnectionStatusViewModel]

    public init(rows: [ChainConnectionStatusViewModel]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Circle()
                        .fill(dotColor(for: row.state))
                        .frame(width: 8, height: 8)

                    Text(row.title)
                        .textStyle(.body14Regular())
                        .foregroundStyle(Color.fgPrimary)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(row.stateTitle)
                            .textStyle(.caption12Regular())
                            .foregroundStyle(Color.fgSecondary)

                        if let latencyText = row.latencyText {
                            Text(latencyText)
                                .textStyle(.caption12Regular())
                                .foregroundStyle(Color.fgSecondary)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Rows arrive through a UIKit configuration assignment, so there is no ambient
                // withAnimation to inherit from.
                .animation(.default, value: row.latencyText)
            }
        }
        .padding(16)
    }

    private func dotColor(for state: ChainConnectionState) -> Color {
        switch state {
        case .connected:
            .bgStatusSuccess
        case .connecting:
            .bgStatusWarning
        case .offline:
            .bgStatusError
        }
    }
}
