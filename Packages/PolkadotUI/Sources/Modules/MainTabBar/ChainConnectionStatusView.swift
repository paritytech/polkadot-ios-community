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

    public init(
        id: String,
        title: String,
        state: ChainConnectionState,
        stateTitle: String
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.stateTitle = stateTitle
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

                    Text(row.stateTitle)
                        .textStyle(.caption12Regular())
                        .foregroundStyle(Color.fgSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
