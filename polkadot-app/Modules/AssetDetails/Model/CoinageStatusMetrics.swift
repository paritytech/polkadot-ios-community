#if TESTNET_FEATURE
    import Coinage
    import CoreGraphics

    /// Shared geometry and scale conversions for the holding depictions, so the voucher bars, the
    /// coin provenance and the summary bar cannot drift apart.
    enum CoinageStatusMetrics {
        /// Height of every depiction — roughly the height of the row's amount text, so coin and
        /// voucher rows come out the same height.
        static let barHeight: CGFloat = 16
        static let summaryBarHeight: CGFloat = 20
        static let outlineWidth: CGFloat = 1
        /// Thicker than the black outline, per the coin circles' red margin.
        static let circleStrokeWidth: CGFloat = 1.8
        /// Gap between circles, and between the two bars of a voucher row.
        static let itemSpacing: CGFloat = 3
        /// Gap between the stacked red and orange bars, so the pair still totals ``barHeight``.
        static let stackSpacing: CGFloat = 3
        /// Leftover column narrower than this reads as a sliver rather than a bar, so the stacked
        /// pair is dropped instead of drawn into it.
        static let minimumVisibleWidth: CGFloat = 6

        /// Floor for a bar whose score is high enough to compute a near-zero length: square, so it
        /// still registers without claiming length it has not earned. Squareness is what keeps it
        /// apart from a provenance circle — see ``solidBarCornerRadius``.
        static let minimumBarWidth: CGFloat = barHeight

        /// Well short of a capsule's `height / 2`, so a minimum-width bar reads as a rounded square
        /// rather than as one of the coin provenance circles.
        static let solidBarCornerRadius: CGFloat = 4

        /// Height of each bar in the stacked pair standing in for unknown provenance. The pair and
        /// the gap between them come to less than ``barHeight`` — they read as a lighter mark than a
        /// solid bar, which is the point.
        static let unknownBarHeight: CGFloat = 4
        static let maximumInnerDots = 4

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
    }
#endif
