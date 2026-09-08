#if TESTNET_FEATURE
    import DesignSystem
    import SwiftUI

    /// Diagonal red-and-white stripes sliding leftwards — the depiction for value that is still
    /// gaining privacy in a recycler.
    ///
    /// The pattern repeats every `stripeWidth * 2`, so sliding by exactly one period and snapping back
    /// is seamless. Only a static layer is offset, which keeps the animation off the main thread even
    /// with a row per holding.
    ///
    /// Two things have to hold for the wrap to be invisible, and both are about coverage rather than
    /// timing: the drawn pattern must extend past the layer's own bounds — a leaning stripe's far
    /// corner is clipped, so drawing only to the edge leaves a wedge of bare background — and the
    /// layer must be wide enough to still cover the viewport after a full period of travel.
    struct BarberPole: View {
        var stripeWidth: CGFloat = 5
        /// Horizontal run per unit of height — the stripes' lean.
        var slant: CGFloat = 0.7
        var periodDuration: Double = 0.6

        @State private var isSliding = false

        var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                let period = Self.period(forStripeWidth: stripeWidth)
                let margin = period + size.height * slant

                ZStack(alignment: .leading) {
                    Color.fgPrimary

                    Canvas { context, canvasSize in
                        Self.drawStripes(
                            in: &context,
                            size: canvasSize,
                            stripeWidth: stripeWidth,
                            slant: slant
                        )
                    }
                    .frame(width: size.width + margin * 2, height: size.height)
                    .offset(x: isSliding ? -margin - period : -margin)
                    .animation(
                        .linear(duration: periodDuration).repeatForever(autoreverses: false),
                        value: isSliding
                    )
                }
                // Leading, not the default centre: the stripe layer is deliberately wider than the
                // frame, and centring it would shift it half its overdraw before the offset below
                // even applies — which starves the right edge partway through each slide.
                .frame(width: size.width, height: size.height, alignment: .leading)
                .clipped()
                .onAppear { isSliding = true }
            }
        }
    }

    private extension BarberPole {
        static func period(forStripeWidth stripeWidth: CGFloat) -> CGFloat {
            stripeWidth * 2
        }

        /// Fills the canvas with stripes, starting and ending a full stripe-and-lean beyond its
        /// bounds. The clip then removes only overshoot, so every point inside is patterned — no
        /// wedge is left where a leaning stripe crosses an edge.
        ///
        /// The pattern's phase is anchored to the canvas, not to the animation, so offsetting the
        /// whole canvas by one period reproduces an identical pattern.
        static func drawStripes(
            in context: inout GraphicsContext,
            size: CGSize,
            stripeWidth: CGFloat,
            slant: CGFloat
        ) {
            let period = period(forStripeWidth: stripeWidth)
            let lean = size.height * slant
            let overshoot = lean + period

            var origin = -overshoot

            while origin < size.width + overshoot {
                context.fill(
                    stripe(at: origin, height: size.height, stripeWidth: stripeWidth, lean: lean),
                    with: .color(Color.fgError)
                )
                origin += period
            }
        }

        static func stripe(
            at origin: CGFloat,
            height: CGFloat,
            stripeWidth: CGFloat,
            lean: CGFloat
        ) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: origin, y: height))
            path.addLine(to: CGPoint(x: origin + lean, y: 0))
            path.addLine(to: CGPoint(x: origin + lean + stripeWidth, y: 0))
            path.addLine(to: CGPoint(x: origin + stripeWidth, y: height))
            path.closeSubpath()

            return path
        }
    }
#endif
