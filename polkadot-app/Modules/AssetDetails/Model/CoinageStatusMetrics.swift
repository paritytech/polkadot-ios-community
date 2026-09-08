#if TESTNET_FEATURE
    import Coinage
    import DesignSystem
    import SwiftUI
    import UIKit

    /// Shared geometry and scale conversions for the holding depictions, so the voucher bars, the
    /// coin provenance and the summary bar cannot drift apart.
    ///
    /// The values come from the design's export, which is 1:1 points.
    enum CoinageStatusMetrics {
        /// Height of every depiction, and so also the diameter of a provenance circle.
        static let barHeight: CGFloat = 21
        static let summaryBarHeight: CGFloat = 20
        static let outlineWidth: CGFloat = 1
        /// Ring around a provenance circle. Thicker than ``outlineWidth`` so it reads as part of the
        /// mark rather than as a separation from the surface behind it.
        static let circleStrokeWidth: CGFloat = 2
        /// Gap between circles, and between the two bars of a voucher row.
        static let itemSpacing: CGFloat = 4
        /// Gap between the stacked red and orange bars.
        static let stackSpacing: CGFloat = 4
        /// Leftover column narrower than this reads as a sliver rather than a bar, so the stacked
        /// pair is dropped instead of drawn into it.
        static let minimumVisibleWidth: CGFloat = 6

        /// Floor for a bar whose score is high enough to compute a near-zero length: square, so it
        /// still registers without claiming length it has not earned. Squareness is what keeps it
        /// apart from a provenance circle — see ``solidBarCornerRadius``.
        static let minimumBarWidth: CGFloat = barHeight

        /// Well short of a capsule's `height / 2`, so a minimum-width bar reads as a rounded square
        /// rather than as one of the coin provenance circles.
        static let solidBarCornerRadius: CGFloat = 5.5

        /// Height of each bar in the stacked pair standing in for unknown provenance. The pair and
        /// the gap between them come to less than ``barHeight`` — they read as a lighter mark than a
        /// solid bar, which is the point.
        static let unknownBarHeight: CGFloat = 3
        static let maximumInnerDots = 4

        /// Inner dots sit on a fixed pitch, clustered at the middle of the circle rather than spread
        /// around its edge, which keeps four of them legible inside ``barHeight``.
        static let innerDotSize: CGFloat = 4
        static let innerDotCornerRadius: CGFloat = 2
        static let innerDotPitch: CGFloat = 6

        /// Chip standing in for the hops that did not fit the column. Sized to its label, with a
        /// floor so a one-digit count still reads as a chip rather than a dot.
        static let overflowChipMinimumWidth: CGFloat = 26
        static let overflowChipPadding: CGFloat = 6

        /// Swatch beside each summary figure, keying it to a section of the bar above.
        static let legendSwatchSize: CGFloat = 12
        static let legendSwatchCornerRadius: CGFloat = 3

        /// Opacity of `fgError` used to fill a provenance circle. Composited over ``plate``, which is
        /// theme-independent, so the resulting dark red is too — within a few units of the design's
        /// own swatch.
        static let circleFillOpacity: CGFloat = 0.2

        /// Corner radius of the plate every depiction is drawn on.
        static let plateCornerRadius: CGFloat = 6

        /// Margin of plate left visible around a depiction. Without it a full-height white mark would
        /// meet the row's own background at its top and bottom edges, which on a light theme is the
        /// invisible case the plate exists to prevent.
        static let platePadding: CGFloat = 2

        /// Ground for every depiction, and the summary bar's unfilled track: the theme's own surface
        /// with its brightness held down.
        ///
        /// The mark colours are semantic — white is spendable, red is not, orange is unknown — so they
        /// are pinned and cannot follow the theme, which means they need a dark ground on all five.
        /// A constant near-black slab does that but reads as foreign inside a warm palette, so only
        /// the brightness is pinned and the hue is the theme's: Lisbon gets a dark brown, Malta a dark
        /// green. White still lands at 14:1 or better everywhere, and the pinned red and orange at
        /// 3.2:1 and 6.8:1 at worst.
        static var plate: Color {
            let surface = UIColor(Color.bgSurfaceMain)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0

            guard surface.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
                return plateFallback
            }

            return Color(
                UIColor(
                    hue: hue,
                    saturation: min(saturation * plateSaturationBoost, plateMaximumSaturation),
                    brightness: plateBrightness,
                    alpha: 1
                )
            )
        }

        /// A pale surface carries little saturation, so it is amplified to keep the theme's character
        /// readable once the brightness is pinned this far down.
        private static let plateSaturationBoost: CGFloat = 2
        private static let plateMaximumSaturation: CGFloat = 0.5
        private static let plateBrightness: CGFloat = 0.16

        /// For a surface that cannot be read as hue, saturation and brightness.
        private static let plateFallback = Color(red: 28 / 255, green: 28 / 255, blue: 34 / 255)

        /// Fraction of the column a score occupies: `1 − √(score/100)`.
        ///
        /// Inverted on purpose — a highly fungible holding draws a *short* bar, and a poorly
        /// fungible one stretches across the column.
        static func fraction(forScore score: UInt8) -> CGFloat {
            let scale = CGFloat(CoinageConstants.fullFungibility)
            let clamped = min(max(CGFloat(score), 0), scale)

            return 1 - (clamped / scale).squareRoot()
        }

        /// Inner dots drawn inside a provenance circle: one per sibling of the hop, capped so a
        /// large bundle stays legible.
        static func innerDots(forCount count: UInt8) -> Int {
            min(max(Int(count) - 1, 0), maximumInnerDots)
        }

        /// Dot centres for a cluster, as offsets from the circle's centre in points.
        ///
        /// Laid out by hand rather than on a ring: one centred, two abreast, three as an apex-up
        /// triangle, four as a square. Offsets are in units of ``innerDotPitch``, so the cluster
        /// scales with the dot size instead of with the circle.
        static func innerDotOffsets(forDots dots: Int) -> [CGPoint] {
            let pitch = innerDotPitch

            let units: [CGPoint] =
                switch min(max(dots, 0), maximumInnerDots) {
                case 1: [CGPoint(x: 0, y: 0)]
                case 2: [CGPoint(x: -0.5, y: 0), CGPoint(x: 0.5, y: 0)]
                case 3: [
                        CGPoint(x: 0, y: -0.6),
                        CGPoint(x: -0.5333, y: 0.4),
                        CGPoint(x: 0.5333, y: 0.4)
                    ]
                case 4: [
                        CGPoint(x: -0.5, y: -0.5),
                        CGPoint(x: 0.5, y: -0.5),
                        CGPoint(x: -0.5, y: 0.5),
                        CGPoint(x: 0.5, y: 0.5)
                    ]
                default: []
                }

            return units.map { CGPoint(x: $0.x * pitch, y: $0.y * pitch) }
        }
    }
#endif

#if TESTNET_FEATURE
    import SwiftUI

    extension View {
        /// Puts a depiction on the constant dark plate its colours are calibrated against, leaving a
        /// margin of it visible on every side so a white mark is always framed.
        func coinagePlate(
            cornerRadius: CGFloat = CoinageStatusMetrics.plateCornerRadius
        ) -> some View {
            padding(CoinageStatusMetrics.platePadding)
                .background(
                    CoinageStatusMetrics.plate,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
        }
    }
#endif
