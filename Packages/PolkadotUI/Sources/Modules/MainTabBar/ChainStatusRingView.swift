import SwiftUI
import DesignSystem

/// Per-chain status indicator. The arc length carries block freshness and is always drawn in
/// `.fgPrimary`; the centre dot is the only coloured element, carrying connection state refined
/// by ping while connected.
struct ChainStatusRingView: View, Hashable {
    private static let freshnessWindow: TimeInterval = 20
    private static let fastLatency: Duration = .milliseconds(150)
    private static let mediumLatency: Duration = .milliseconds(400)

    let row: ChainConnectionStatusViewModel

    /// Stroke and dot scale with this, so the two hosts stay visually the same mark at
    /// different sizes — the strip is bound by its 20pt band, the panel is not.
    var diameter: CGFloat = 16

    var body: some View {
        // The arc drains with no new data arriving, so the tick has to come from the view —
        // expressing the passage of time as a per-second row push would reassign the UIKit
        // configuration once a second for a value the view can compute itself.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = freshness(at: context.date)

            ZStack {
                Circle()
                    .stroke(Color.fgPrimary.opacity(0.2), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        Color.fgPrimary,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: fraction)

                ChainStatusRingDot(
                    color: dotColor,
                    diameter: dotDiameter,
                    isPulsing: row.state == .connecting
                )
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityElement(children: .ignore)
        // A plain interpolated Text is treated as a localizable format string, which registers
        // a "%@, %@" entry in the package catalog.
        .accessibilityLabel(Text(verbatim: "\(row.title), \(row.stateTitle)"))
    }
}

private extension ChainStatusRingView {
    var lineWidth: CGFloat { diameter / 8 }

    var dotDiameter: CGFloat { diameter * 0.375 }

    var dotColor: Color {
        switch row.state {
        case .connected:
            connectedDotColor
        case .connecting:
            .fgTertiary
        case .offline:
            .bgStatusError
        }
    }

    /// Grey until the first probe lands — an unsampled chain is not a slow one.
    var connectedDotColor: Color {
        guard let latency = row.latency else {
            return .fgTertiary
        }

        if latency <= Self.fastLatency {
            return .fgPrimary
        } else if latency <= Self.mediumLatency {
            return .bgStatusWarning
        } else {
            return .bgStatusError
        }
    }

    func freshness(at date: Date) -> Double {
        guard row.state == .connected, let lastBlockDate = row.lastBlockDate else {
            return 0
        }

        let age = date.timeIntervalSince(lastBlockDate)

        return 1 - min(max(age / Self.freshnessWindow, 0), 1)
    }
}

/// Owns the repeating animation's `@State` so `ChainStatusRingView` keeps the synthesized
/// `Hashable` conformance that content reuse depends on.
private struct ChainStatusRingDot: View {
    let color: Color
    let diameter: CGFloat
    let isPulsing: Bool

    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .opacity(isDimmed ? 0.3 : 1)
            .animation(pulseAnimation, value: isDimmed)
            .onAppear { isDimmed = isPulsing }
            .onChange(of: isPulsing) { _, newValue in isDimmed = newValue }
    }

    private var pulseAnimation: Animation {
        isPulsing
            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            : .easeInOut(duration: 0.2)
    }
}
