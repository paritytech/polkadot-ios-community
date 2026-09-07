import SwiftUI
import DesignSystem

/// Numeric readout of every monitored connection. It repeats the top strip's ring at a larger
/// size so the two read as the same mark, and prints the figures behind the grade beside it.
public struct ConnectionStatusPanelView: View, Hashable {
    public let rows: [ChainConnectionStatusViewModel]

    public init(rows: [ChainConnectionStatusViewModel]) {
        self.rows = rows
    }

    public var body: some View {
        // `ChainStatusProvider` drops identical row sets, so a stalled chain stops emitting
        // entirely. Block age therefore ticks on a view-local timeline rather than on emissions,
        // otherwise it would freeze exactly when the panel is opened to diagnose the stall.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rows) { row in
                    rowView(row, now: context.date)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The hosting panel pins its content edge to edge, so the inset is the view's own.
            .padding(16)
        }
    }
}

private extension ConnectionStatusPanelView {
    static let placeholder = "—"

    /// `secondsMinutesAbbreviated` is a computed property, so reading it per row per tick would
    /// build a formatter four times a second while the panel is open.
    static let blockAgeFormatter = DateComponentsFormatter.secondsMinutesAbbreviated

    func rowView(_ row: ChainConnectionStatusViewModel, now: Date) -> some View {
        HStack(spacing: 12) {
            // The ring labels itself "title, stateTitle", which the row's own text already says.
            // Hiding it here rather than ignoring the row's children keeps the figures readable.
            ChainStatusRingView(viewModel: row, diameter: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(verbatim: row.title)
                        .font(.caption12Regular())
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(verbatim: row.stateTitle)
                        .font(.caption12Regular())
                        .foregroundStyle(Color.fgSecondary)
                        .lineLimit(1)
                }

                HStack(alignment: .top, spacing: 12) {
                    figureView(
                        label: String(localized: .Common.connectionStatusLatencyLabel),
                        value: latencyText(row.latency)
                    )
                    figureView(
                        label: String(localized: .Common.connectionStatusBlockLabel),
                        value: blockAgeText(row.lastBlockDate, now: now)
                    )
                    figureView(
                        label: String(localized: .Common.connectionStatusFinalityLabel),
                        value: finalityText(row.finalityLag)
                    )
                }
            }
        }
    }

    /// Absent figures render an em dash rather than collapsing, so row height stays stable while a
    /// connection transitions between states. Every label is `lineLimit(1)` for the same reason:
    /// the panel measures its content only when a configuration is pushed, so text that wrapped
    /// on a timeline tick would grow the content without resizing the panel around it.
    func figureView(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.caption12Regular())
                .foregroundStyle(Color.fgSecondary)
                .lineLimit(1)

            Text(verbatim: value)
                .font(.caption12Regular())
                .foregroundStyle(Color.fgPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func latencyText(_ latency: Duration?) -> String {
        guard let latency else {
            return Self.placeholder
        }

        let milliseconds = latency.components.seconds * 1_000
            + latency.components.attoseconds / 1_000_000_000_000_000
        return "\(milliseconds) ms"
    }

    func blockAgeText(_ lastBlockDate: Date?, now: Date) -> String {
        guard
            let lastBlockDate,
            let age = Self.blockAgeFormatter.string(
                from: max(0, now.timeIntervalSince(lastBlockDate))
            )
        else {
            return Self.placeholder
        }

        return String(localized: .Common.connectionStatusBlockAgeValue(age))
    }

    func finalityText(_ finalityLag: Int?) -> String {
        guard let finalityLag else {
            return Self.placeholder
        }

        return String(localized: .Common.connectionStatusFinalityValue(finalityLag))
    }
}
