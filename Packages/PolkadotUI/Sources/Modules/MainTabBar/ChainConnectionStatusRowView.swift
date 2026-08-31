import SwiftUI
import DesignSystem

struct ChainConnectionStatusRowView: View, Hashable {
    let row: ChainConnectionStatusViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(dotColor(for: row.state))
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .textStyle(.body14Regular())
                    .foregroundStyle(Color.fgPrimary)

                detailLine()
                    .contentTransition(.numericText())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Rows arrive through a UIKit configuration assignment, so there is no ambient
        // withAnimation to inherit from.
        .animation(.default, value: row.latencyText)
    }

    /// Separators are interleaved between the present items so an absent piece can never leave a
    /// leading or doubled `·`.
    private func detailLine() -> some View {
        let items: [Text?] = [
            Text(row.stateTitle),
            row.latencyText.map { Text($0) },
            row.blockText.map { Text($0) },
            // SwiftUI self-updates a relative date label, so the age ticks without a per-second
            // configuration push through the UIKit host.
            row.lastBlockDate.map { Text($0, style: .relative) }
        ]

        return HStack(spacing: 4) {
            ForEach(Array(items.compactMap { $0 }.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Text("·").textStyle(.caption12Regular())
                }

                item.textStyle(.caption12Regular())
            }
        }
        .foregroundStyle(Color.fgSecondary)
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
