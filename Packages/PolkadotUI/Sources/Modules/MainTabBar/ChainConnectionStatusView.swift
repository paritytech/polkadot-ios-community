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
    public let latency: Duration?
    public let lastBlockDate: Date?

    public init(
        id: String,
        title: String,
        state: ChainConnectionState,
        stateTitle: String,
        latency: Duration?,
        lastBlockDate: Date?
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.stateTitle = stateTitle
        self.latency = latency
        self.lastBlockDate = lastBlockDate
    }
}

public struct ChainConnectionStatusView: View, Hashable {
    /// The panel has room the 20pt top strip does not, so the same ring is drawn larger here.
    private static let ringDiameter: CGFloat = 40

    public let rows: [ChainConnectionStatusViewModel]

    public init(rows: [ChainConnectionStatusViewModel]) {
        self.rows = rows
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(rows) { row in
                column(for: row)
            }
        }
        .padding(16)
    }

    private func column(for row: ChainConnectionStatusViewModel) -> some View {
        VStack(spacing: 8) {
            // `Text(_: String)` rather than an interpolated literal — the latter is treated as a
            // localizable key and registers an entry in the package catalog.
            Text(row.title)
                .textStyle(.caption12Regular())
                .foregroundStyle(Color.fgSecondary)
                .lineLimit(2)

            ChainStatusRingView(row: row, diameter: Self.ringDiameter)
        }
        .frame(maxWidth: .infinity)
        // The name is visible now, so the ring's own label would make VoiceOver say it twice.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(row.title), \(row.stateTitle)"))
    }
}
