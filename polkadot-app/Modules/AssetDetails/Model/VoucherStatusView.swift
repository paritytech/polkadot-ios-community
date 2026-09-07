#if TESTNET_FEATURE
    import Coinage
    import DesignSystem
    import SwiftUI

    /// A voucher's recycler status: a solid bar for the anonymity its recycler can ever reach,
    /// followed by a barber pole covering the part still being earned.
    ///
    /// Both lengths are inverted scores, so the pair together reaches `1 − √(fungibility/100)` of
    /// the column and shrinks towards nothing as the recycler fills. Neither bar ever disappears —
    /// a voucher always has both a ceiling and a gap to it, even when both round to nothing.
    struct VoucherStatusView: View {
        struct Model: Equatable {
            /// Frozen when the voucher entered its ring — the best the ring can still do.
            let maxFungibility: UInt8
            /// The ring's fungibility right now.
            let fungibility: UInt8
            /// Whether the current strategy would let this voucher be unloaded immediately.
            let isUnloadable: Bool
        }

        let model: Model

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = CoinageStatusMetrics.barHeight
                let layout = Self.layout(for: model, width: width)

                let solidShape = RoundedRectangle(cornerRadius: CoinageStatusMetrics.solidBarCornerRadius)

                ZStack(alignment: .leading) {
                    solidShape
                        .fill(model.isUnloadable ? Color.fgStaticWhite : Color.fgError)
                        .frame(width: layout.solidWidth, height: height)
                        .overlay(
                            solidShape.stroke(Color.black, lineWidth: CoinageStatusMetrics.outlineWidth)
                        )

                    BarberPole()
                        .frame(width: layout.poleWidth, height: height)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.black, lineWidth: CoinageStatusMetrics.outlineWidth)
                        )
                        .offset(x: layout.poleOrigin)
                }
                .frame(width: width, height: height, alignment: .leading)
            }
            .frame(height: CoinageStatusMetrics.barHeight)
        }
    }

    extension VoucherStatusView {
        struct Layout: Equatable {
            let solidWidth: CGFloat
            let poleOrigin: CGFloat
            let poleWidth: CGFloat
        }

        /// Lays the pair out so the solid bar spans `1 − √(max/100)` of the column and the pole ends
        /// at `1 − √(current/100)`, subject to two rules.
        ///
        /// Both bars have a minimum width, so a score that rounds to a zero-length bar still leaves a
        /// mark. When enforcing the pole's minimum would push it past the column, the pole is pinned
        /// to the right edge and the solid bar gives up the room instead — the pole is the reading
        /// that changes, so it is the one that must stay legible.
        ///
        /// `max >= current` holds for any single reading, but the maximum is frozen at ring entry
        /// while the current score keeps updating — and the chain decrements its unloaded count on a
        /// failed dispatch — so a later reading can invert the pair. Clamping keeps the pole's length
        /// non-negative instead of drawing it backwards.
        static func layout(for model: Model, width: CGFloat) -> Layout {
            let minimum = CoinageStatusMetrics.minimumBarWidth
            let spacing = CoinageStatusMetrics.itemSpacing

            let solidFraction = CoinageStatusMetrics.fraction(forScore: model.maxFungibility)
            let poleFraction = max(
                CoinageStatusMetrics.fraction(forScore: model.fungibility),
                solidFraction
            )

            var solidWidth = max(solidFraction * width, minimum)
            var poleEnd = max(poleFraction * width, solidWidth + spacing + minimum)

            if poleEnd > width {
                poleEnd = width
                solidWidth = max(min(solidWidth, width - minimum - spacing), 0)
            }

            let poleOrigin = solidWidth + spacing

            return Layout(
                solidWidth: solidWidth,
                poleOrigin: poleOrigin,
                poleWidth: max(poleEnd - poleOrigin, 0)
            )
        }
    }
#endif
