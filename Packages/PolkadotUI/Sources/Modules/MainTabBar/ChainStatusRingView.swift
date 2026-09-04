import SwiftUI
import DesignSystem

/// Per-chain status indicator. The arc length carries health (block age, finality stall, and ping
/// combined worst-of) and is colored by health score; the centre dot reflects connection state only.
struct ChainStatusRingView: View, Hashable {
    let viewModel: ChainConnectionStatusViewModel

    /// Stroke and dot scale with this, so the two hosts stay visually the same mark at
    /// different sizes — the strip is bound by its 20pt band, the panel is not.
    var diameter: CGFloat = 16

    var body: some View {
        // The arc drains with no new data arriving, so the tick has to come from the view —
        // expressing the passage of time as a per-second row push would reassign the UIKit
        // configuration once a second for a value the view can compute itself.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let health = ChainHealth.score(for: viewModel, at: context.date)
            let arcColor = ChainHealth.arcColor(for: health)

            ZStack {
                Circle()
                    .stroke(Color.fgPrimary.opacity(0.2), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: health)
                    .stroke(
                        arcColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: health)

                ChainStatusRingDot(
                    color: dotColor,
                    diameter: dotDiameter,
                    isPulsing: viewModel.state == .connecting
                )
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityElement(children: .ignore)
        // A plain interpolated Text("...") would be treated as a localizable format string and
        // register a "%@, %@" entry in the package catalog; verbatim avoids localization.
        .accessibilityLabel(Text(verbatim: "\(viewModel.title), \(viewModel.stateTitle)"))
    }
}

private extension ChainStatusRingView {
    var lineWidth: CGFloat { diameter / 8 }

    var dotDiameter: CGFloat { diameter * 0.375 }

    var dotColor: Color {
        switch viewModel.state {
        case .connected:
            .fgPrimary
        case .connecting:
            .fgTertiary
        case .offline:
            .bgStatusError
        }
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

private extension ChainHealth {
    static func arcColor(for health: Double) -> Color {
        if health > 0.6 {
            .fgPrimary
        } else if health > 0.3 {
            .bgStatusWarning
        } else {
            .bgStatusError
        }
    }
}
