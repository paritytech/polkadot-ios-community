#if TESTNET_FEATURE
    import DesignSystem
    import SwiftUI

    /// Value-weighted split of everything the user holds: spendable coins, value still gaining
    /// privacy in a recycler, and coins the strategy will not release.
    ///
    /// The three shares are computed from the same classification as the balance figures shown above
    /// it, so the bar always accounts for exactly the total balance.
    struct CoinageCompositionBar: View {
        struct Model: Equatable {
            let spendableShare: Double
            let loadingShare: Double
            let unspendableShare: Double

            static let empty = Model(spendableShare: 0, loadingShare: 0, unspendableShare: 0)

            var isEmpty: Bool {
                spendableShare + loadingShare + unspendableShare <= 0
            }
        }

        let model: Model

        var body: some View {
            GeometryReader { geometry in
                let widths = Self.widths(for: model, totalWidth: geometry.size.width)

                HStack(spacing: 0) {
                    Color.fgStaticWhite
                        .frame(width: widths.spendable)

                    BarberPole()
                        .frame(width: widths.loading)

                    Color.fgError
                        .frame(width: widths.unspendable)

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: CoinageStatusMetrics.summaryBarHeight)
                .background(Color.bgSurfaceMain)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.black, lineWidth: CoinageStatusMetrics.outlineWidth)
                )
            }
            .frame(height: CoinageStatusMetrics.summaryBarHeight)
        }
    }

    extension CoinageCompositionBar {
        struct SectionWidths: Equatable {
            let spendable: CGFloat
            let loading: CGFloat
            let unspendable: CGFloat

            static let none = SectionWidths(spendable: 0, loading: 0, unspendable: 0)
        }

        /// The last section takes the rounding remainder, so the sections always fill the bar
        /// exactly and no seam appears at the right edge.
        static func widths(for model: Model, totalWidth: CGFloat) -> SectionWidths {
            guard !model.isEmpty, totalWidth > 0 else { return .none }

            let spendable = (totalWidth * model.spendableShare).rounded()
            let loading = (totalWidth * model.loadingShare).rounded()

            return SectionWidths(
                spendable: spendable,
                loading: loading,
                unspendable: max(totalWidth - spendable - loading, 0)
            )
        }
    }
#endif
