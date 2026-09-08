#if TESTNET_FEATURE
    import DesignSystem
    import SwiftUI

    /// Value-weighted picture of the three balance figures shown above it: available now, gaining
    /// privacy, and pending.
    ///
    /// Each section is the same bucket as the row above it, so the bar is a legend-free depiction of
    /// those numbers rather than a second, differently-cut summary. Coins and vouchers land in
    /// whichever bucket the strategy puts them in — a voucher ready to unload counts as available,
    /// exactly as the figure above does.
    struct CoinageCompositionBar: View {
        struct Model: Equatable {
            let availableNowShare: Double
            let gainingPrivacyShare: Double
            let pendingShare: Double

            static let empty = Model(
                availableNowShare: 0,
                gainingPrivacyShare: 0,
                pendingShare: 0
            )

            var isEmpty: Bool {
                availableNowShare + gainingPrivacyShare + pendingShare <= 0
            }
        }

        let model: Model

        var body: some View {
            GeometryReader { geometry in
                let widths = Self.widths(for: model, totalWidth: geometry.size.width)

                HStack(spacing: 0) {
                    Color.fgPrimary
                        .frame(width: widths.availableNow)

                    BarberPole()
                        .frame(width: widths.gainingPrivacy)

                    Color.fgError
                        .frame(width: widths.pending)

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: CoinageStatusMetrics.summaryBarHeight)
                .background(Color.bgSurfaceMain)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.strokeCutout, lineWidth: CoinageStatusMetrics.outlineWidth)
                )
            }
            .frame(height: CoinageStatusMetrics.summaryBarHeight)
        }
    }

    extension CoinageCompositionBar {
        struct SectionWidths: Equatable {
            let availableNow: CGFloat
            let gainingPrivacy: CGFloat
            let pending: CGFloat

            static let none = SectionWidths(availableNow: 0, gainingPrivacy: 0, pending: 0)
        }

        /// The last section takes the rounding remainder, so the sections always fill the bar
        /// exactly and no seam appears at the right edge.
        static func widths(for model: Model, totalWidth: CGFloat) -> SectionWidths {
            guard !model.isEmpty, totalWidth > 0 else { return .none }

            let availableNow = (totalWidth * model.availableNowShare).rounded()
            let gainingPrivacy = (totalWidth * model.gainingPrivacyShare).rounded()

            return SectionWidths(
                availableNow: availableNow,
                gainingPrivacy: gainingPrivacy,
                pending: max(totalWidth - availableNow - gainingPrivacy, 0)
            )
        }
    }
#endif
