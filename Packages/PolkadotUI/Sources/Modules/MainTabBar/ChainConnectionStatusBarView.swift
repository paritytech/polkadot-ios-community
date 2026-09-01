import SwiftUI
import DesignSystem

public struct ChainConnectionStatusBarView: View, Hashable {
    public static let preferredHeight: CGFloat = 20

    public let rows: [ChainConnectionStatusViewModel]

    public init(rows: [ChainConnectionStatusViewModel]) {
        self.rows = rows
    }

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(rows) { row in
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(row.state.statusColor)
                    .symbolEffect(
                        .variableColor.iterative.dimInactiveLayers,
                        options: .repeating,
                        isActive: row.state == .connecting
                    )
                    .accessibilityLabel(Text(verbatim: "\(row.title), \(row.stateTitle)"))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.preferredHeight)
    }
}

extension ChainConnectionState {
    var statusColor: Color {
        switch self {
        case .connected:
            .bgStatusSuccess
        case .connecting:
            .bgStatusWarning
        case .offline:
            .bgStatusError
        }
    }
}
