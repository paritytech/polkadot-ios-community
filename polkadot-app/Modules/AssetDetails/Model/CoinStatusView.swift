#if TESTNET_FEATURE
    import Coinage
    import DesignSystem
    import SwiftUI

    /// A coin's provenance: one circle per hop, oldest at the left, with inner dots for the
    /// siblings the hop moved or produced alongside it.
    ///
    /// A coin that has never hopped shows a single bar sized by its recycler's fungibility instead.
    /// Where provenance runs out — an unknown recycler, or column left over past the last circle —
    /// the stacked red-and-orange pair stands in for what is not known.
    struct CoinStatusView: View {
        struct Model: Equatable {
            /// One entry per hop, oldest first: the inner-dot count already resolved from the hop's
            /// `bundleSize` or `fanout`.
            let hopDots: [Int]
            /// Fungibility of the recycler the coin came out of. `nil` when it is not known.
            let fungibility: UInt8?
            /// Whether the current strategy leaves this coin spendable right now.
            let isSpendable: Bool
        }

        let model: Model

        var body: some View {
            Canvas { context, size in
                Self.draw(model, in: &context, size: size)
            }
            .frame(height: CoinageStatusMetrics.barHeight)
        }
    }

    private extension CoinStatusView {
        static func draw(_ model: Model, in context: inout GraphicsContext, size: CGSize) {
            guard !model.hopDots.isEmpty else {
                drawUnhopped(model, in: &context, size: size)
                return
            }

            let drawn = drawCircles(model.hopDots, in: &context, size: size)

            let origin = drawn.usedWidth + CoinageStatusMetrics.itemSpacing
            let remaining = size.width - origin

            guard remaining >= CoinageStatusMetrics.minimumVisibleWidth else { return }

            drawUnknown(
                in: &context,
                rect: CGRect(x: origin, y: 0, width: remaining, height: size.height)
            )
        }

        static func drawUnhopped(_ model: Model, in context: inout GraphicsContext, size: CGSize) {
            guard let fungibility = model.fungibility else {
                drawUnknown(in: &context, rect: CGRect(origin: .zero, size: size))
                return
            }

            // A perfectly fungible recycler scores a zero-length bar; the minimum keeps a mark.
            let width = max(
                CoinageStatusMetrics.fraction(forScore: fungibility) * size.width,
                CoinageStatusMetrics.minimumBarWidth
            )
            let inset = CoinageStatusMetrics.outlineWidth / 2
            let rect = CGRect(
                x: inset,
                y: inset,
                width: max(width - CoinageStatusMetrics.outlineWidth, 0),
                height: size.height - CoinageStatusMetrics.outlineWidth
            )
            let path = Path(
                roundedRect: rect,
                cornerRadius: CoinageStatusMetrics.solidBarCornerRadius
            )

            context.fill(path, with: .color(model.isSpendable ? Color.fgStaticWhite : Color.fgError))
            context.stroke(path, with: .color(Color.black), lineWidth: CoinageStatusMetrics.outlineWidth)
        }

        /// Draws as many whole circles as fit. A circle that would be clipped is dropped entirely
        /// rather than drawn part-way.
        static func drawCircles(
            _ hopDots: [Int],
            in context: inout GraphicsContext,
            size: CGSize
        ) -> (count: Int, usedWidth: CGFloat) {
            let diameter = size.height
            let spacing = CoinageStatusMetrics.itemSpacing
            let fitting = Int((size.width + spacing) / (diameter + spacing))
            let count = min(max(fitting, 0), hopDots.count)

            guard count > 0 else { return (0, 0) }

            for index in 0 ..< count {
                let rect = CGRect(
                    x: CGFloat(index) * (diameter + spacing),
                    y: 0,
                    width: diameter,
                    height: diameter
                )
                drawCircle(dots: hopDots[index], in: &context, rect: rect)
            }

            let usedWidth = CGFloat(count) * diameter + CGFloat(count - 1) * spacing

            return (count, usedWidth)
        }

        static func drawCircle(dots: Int, in context: inout GraphicsContext, rect: CGRect) {
            let inset = CoinageStatusMetrics.circleStrokeWidth / 2
            let outline = Path(ellipseIn: rect.insetBy(dx: inset, dy: inset))

            context.fill(outline, with: .color(Color.fgStaticWhite))
            context.stroke(
                outline,
                with: .color(Color.fgError),
                lineWidth: CoinageStatusMetrics.circleStrokeWidth
            )

            guard dots > 0 else { return }

            let radius = rect.width / 2
            let dotRadius = radius * 0.18
            let center = CGPoint(x: rect.midX, y: rect.midY)

            // A lone sibling reads better centred than parked on the ring.
            guard dots > 1 else {
                fillDot(at: center, radius: dotRadius, in: &context)
                return
            }

            let ringRadius = radius * 0.45

            for index in 0 ..< dots {
                let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(dots)
                let position = CGPoint(
                    x: center.x + cos(angle) * ringRadius,
                    y: center.y + sin(angle) * ringRadius
                )
                fillDot(at: position, radius: dotRadius, in: &context)
            }
        }

        static func fillDot(at center: CGPoint, radius: CGFloat, in context: inout GraphicsContext) {
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(Color.fgError))
        }

        /// The stacked pair standing in for provenance that is not known. Thinner than a solid bar
        /// and centred in the row, so it reads as an absence rather than as a measurement.
        static func drawUnknown(in context: inout GraphicsContext, rect: CGRect) {
            let height = CoinageStatusMetrics.unknownBarHeight
            let total = height * 2 + CoinageStatusMetrics.stackSpacing
            let top = rect.minY + (rect.height - total) / 2

            let topBar = CGRect(x: rect.minX, y: top, width: rect.width, height: height)
            let bottomBar = CGRect(x: rect.minX, y: top + total - height, width: rect.width, height: height)

            context.fill(
                Path(roundedRect: topBar, cornerRadius: height / 2),
                with: .color(Color.fgError)
            )
            context.fill(
                Path(roundedRect: bottomBar, cornerRadius: height / 2),
                with: .color(Color.fgWarning)
            )
        }
    }
#endif
