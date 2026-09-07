#if TESTNET_FEATURE
    import PolkadotUI
    import SwiftUI

    /// Value-weighted composition of the holdings: how much is private, how much is still
    /// loading through the recycler, and how much is publicly traceable.
    ///
    /// Segment lengths are proportions of total value, not counts — a single large coin
    /// outweighs several small ones.
    struct PrivacyCompositionBar: View {
        let model: Model

        struct Model: Equatable {
            /// Proportions of total value; each in `0...1`, summing to 1 unless empty.
            let privateShare: Double
            let loadingShare: Double
            let publicShare: Double

            static let empty = Model(privateShare: 0, loadingShare: 0, publicShare: 0)

            var isEmpty: Bool {
                privateShare + loadingShare + publicShare <= 0
            }
        }

        private let height: CGFloat = 14

        /// The loading state deliberately avoids the warning colour used by mid-band holdings:
        /// loading is a transient process, not a privacy verdict. No design-system blue exists
        /// yet, and `Color(hex:)` is internal to PolkadotUI, so this is spelled out.
        private let loadingColor = Color(red: 0.243, green: 0.482, blue: 0.839)

        var body: some View {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    segment(width: width(for: model.privateShare, in: proxy.size.width))
                        .foregroundStyle(FungibilityBand.high.color)

                    segment(width: width(for: model.loadingShare, in: proxy.size.width))
                        .foregroundStyle(loadingColor)
                        .shimmering(active: model.loadingShare > 0)
                        // Holdings travel public -> loading -> private, which is right to left
                        // in this ordering. The shared shimmer only sweeps left to right, so
                        // the segment is mirrored; being a flat fill, nothing else changes.
                        .scaleEffect(x: -1, y: 1)

                    segment(width: width(for: model.publicShare, in: proxy.size.width))
                        .foregroundStyle(FungibilityBand.low.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgSurfaceMain)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(FungibilityBand.outline, lineWidth: FungibilityBand.outlineWidth)
                }
            }
            .frame(height: height)
        }

        @ViewBuilder
        private func segment(width: CGFloat) -> some View {
            if width > 0 {
                Rectangle().frame(width: width)
            }
        }

        private func width(for share: Double, in total: CGFloat) -> CGFloat {
            guard total > 0, share > 0 else { return 0 }
            return total * CGFloat(share)
        }
    }

    #Preview {
        VStack(spacing: 14) {
            PrivacyCompositionBar(model: .init(privateShare: 0.6, loadingShare: 0.15, publicShare: 0.25))
            PrivacyCompositionBar(model: .init(privateShare: 0.05, loadingShare: 0.5, publicShare: 0.45))
            PrivacyCompositionBar(model: .init(privateShare: 1, loadingShare: 0, publicShare: 0))
            PrivacyCompositionBar(model: .empty)
        }
        .padding()
        .background(Color.bgSurfaceNested)
    }
#endif
