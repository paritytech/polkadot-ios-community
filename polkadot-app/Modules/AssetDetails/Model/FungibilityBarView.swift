#if TESTNET_FEATURE
    import Coinage
    import DesignSystem
    import SwiftUI

    /// Visual, number-free depiction of a holding's fungibility.
    ///
    /// The bar shows the *inverse* of the score, so a highly fungible holding reads as a short
    /// bar and a poorly fungible one as a long bar. The square on the left carries the same
    /// colour and is always visible, so a near-zero-length bar still says something.
    ///
    /// For coins the bar also carries provenance: the recycler is the square, and each hop is a
    /// dot on a chain running left to right. A split hop fans out from the node it *originated*
    /// at — the node before it — so the final dot always reads as "here, now".
    struct FungibilityBarView: View {
        let model: Model

        struct Model: Equatable {
            /// `0...100`. Drives the bar's colour and (inversely) its length.
            let score: UInt8
            /// The recycler's own fungibility, before any hop discount. Colours the square,
            /// so a coin can show a healthy recycler alongside a bar ruined by its hops.
            let recyclerScore: UInt8
            /// Extra branches drawn at the recycler square, i.e. from the first hop if it split.
            let squareBranches: Int
            /// One entry per hop, in order: extra branches contributed by the *following* hop.
            let hopBranches: [Int]

            static let maximumBranches = 5

            /// A voucher has no hops, so its score *is* its recycler's.
            static func voucher(score: UInt8) -> Model {
                Model(score: score, recyclerScore: score, squareBranches: 0, hopBranches: [])
            }

            /// A split into `fanout` outputs keeps one as the chain, so the rest are drawn as
            /// extra branches — capped so a very wide split stays legible.
            static func branches(forFanout fanout: UInt8) -> Int {
                min(max(Int(fanout) - 1, 0), maximumBranches)
            }
        }

        private let barHeight: CGFloat = 22
        private let squareSide: CGFloat = 14
        private let nodeDiameter: CGFloat = 9
        private let nodeSpacing: CGFloat = 22
        private let chainLineWidth: CGFloat = 2.5
        private let fanoutLineWidth: CGFloat = 2

        /// Reaches most of the way to the next dot without touching it.
        private var fanoutLength: CGFloat { nodeSpacing * 0.8 }

        /// Shallow enough that the widest branch still fits inside the bar height.
        private let fanoutMagnitudes: [CGFloat] = [28, 14, 21]

        var body: some View {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(FungibilityBand(score: model.recyclerScore).color)
                    .frame(width: squareSide, height: squareSide)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(FungibilityBand.outline, lineWidth: FungibilityBand.outlineWidth)
                    }

                Canvas { context, size in
                    draw(in: &context, size: size)
                }
                .frame(maxWidth: .infinity)
                .frame(height: barHeight)
            }
        }

        private func draw(in context: inout GraphicsContext, size: CGSize) {
            let radius = size.height / 2
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius)
            context.fill(track, with: .color(.bgSurfaceMain))

            let fillWidth = size.width * inverseFraction
            let fill = Path(
                roundedRect: CGRect(x: 0, y: 0, width: fillWidth, height: size.height),
                cornerRadius: radius
            )
            context.fill(fill, with: .color(band.color))
            context.stroke(fill, with: .color(FungibilityBand.outline), lineWidth: FungibilityBand.outlineWidth)

            // Provenance is drawn over the fill and clipped to it: a chain longer than the bar
            // is simply cut off rather than escaping into the track.
            context.clip(to: fill)
            drawProvenance(in: &context, size: size, fillWidth: fillWidth)
        }

        private func drawProvenance(in context: inout GraphicsContext, size: CGSize, fillWidth: CGFloat) {
            let midY = size.height / 2
            let centers = (0 ..< model.hopBranches.count)
                .map { CGFloat($0 + 1) * nodeSpacing }
                .filter { $0 + nodeDiameter / 2 <= fillWidth }

            // One chain line from the recycler through every dot that fits.
            if let last = centers.last {
                var chain = Path()
                chain.move(to: CGPoint(x: 0, y: midY))
                chain.addLine(to: CGPoint(x: last, y: midY))
                context.stroke(chain, with: .color(band.ink), lineWidth: chainLineWidth)
            }

            if model.squareBranches > 0 {
                // Origin is the recycler square, which sits just outside the bar.
                drawFanout(in: &context, at: CGPoint(x: 0, y: midY), branches: model.squareBranches)
            }

            for (index, center) in centers.enumerated() {
                let branches = model.hopBranches[index]
                if branches > 0 {
                    drawFanout(in: &context, at: CGPoint(x: center, y: midY), branches: branches)
                }
            }

            for center in centers {
                let rect = CGRect(
                    x: center - nodeDiameter / 2,
                    y: midY - nodeDiameter / 2,
                    width: nodeDiameter,
                    height: nodeDiameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(band.ink))
            }
        }

        private func drawFanout(in context: inout GraphicsContext, at origin: CGPoint, branches: Int) {
            for angle in angles(for: branches) {
                let radians = angle * .pi / 180
                var path = Path()
                path.move(to: origin)
                path.addLine(
                    to: CGPoint(
                        x: origin.x + cos(radians) * fanoutLength,
                        y: origin.y + sin(radians) * fanoutLength
                    )
                )
                context.stroke(
                    path,
                    with: .color(band.ink.opacity(0.6)),
                    lineWidth: fanoutLineWidth
                )
            }
        }

        /// Alternates above and below the chain, widest first, so even a single extra branch
        /// reads as a fan rather than a kink in the line.
        private func angles(for branches: Int) -> [CGFloat] {
            (0 ..< branches).map { index in
                let magnitude = fanoutMagnitudes[(index / 2) % fanoutMagnitudes.count]
                return index.isMultiple(of: 2) ? -magnitude : magnitude
            }
        }

        private var inverseFraction: CGFloat {
            let full = CGFloat(CoinageConstants.fullFungibility)
            let inverse = full - CGFloat(min(model.score, CoinageConstants.fullFungibility))
            return inverse / full
        }

        private var band: FungibilityBand {
            FungibilityBand(score: model.score)
        }
    }

    #Preview {
        VStack(alignment: .leading, spacing: 12) {
            FungibilityBarView(model: .voucher(score: 95))
            FungibilityBarView(model: .voucher(score: 60))
            FungibilityBarView(model: .voucher(score: 10))
            FungibilityBarView(model: .init(score: 60, recyclerScore: 100, squareBranches: 1, hopBranches: [0, 0]))
            FungibilityBarView(model: .init(score: 20, recyclerScore: 80, squareBranches: 0, hopBranches: [3, 0, 0, 0]))
            FungibilityBarView(model: .init(
                score: 10,
                recyclerScore: 90,
                squareBranches: 5,
                hopBranches: [1, 2, 3, 4, 5, 0]
            ))
            FungibilityBarView(model: .init(
                score: 0,
                recyclerScore: 40,
                squareBranches: 0,
                hopBranches: Array(repeating: 2, count: 12)
            ))
        }
        .padding()
        .background(Color.bgSurfaceNested)
    }
#endif
