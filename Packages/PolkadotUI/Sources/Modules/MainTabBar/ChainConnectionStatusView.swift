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
    public let blockText: String?
    public let lastBlockDate: Date?

    public init(
        id: String,
        title: String,
        state: ChainConnectionState,
        stateTitle: String,
        latencyText: String?,
        blockText: String?,
        lastBlockDate: Date?
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.stateTitle = stateTitle
        self.latencyText = latencyText
        self.blockText = blockText
        self.lastBlockDate = lastBlockDate
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
                ChainConnectionStatusRowView(row: row)
            }
        }
        .padding(16)
    }
}
