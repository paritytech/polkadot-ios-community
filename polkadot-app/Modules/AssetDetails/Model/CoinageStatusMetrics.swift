import Coinage
import DesignSystem
import SwiftUI

/// Shared geometry and scale conversions for the holding depictions, so the voucher bars, the
/// coin provenance and the summary bar cannot drift apart.
///
/// The values come from the design's export, which is 1:1 points.
enum CoinageStatusMetrics {
    /// Height of every depiction, and so also the diameter of a provenance circle.
    static let barHeight: CGFloat = 21
    static let summaryBarHeight: CGFloat = 20
    /// Height of a level bar. Shorter than ``barHeight`` because a bar carries no internal detail,
    /// unlike a provenance circle, so it costs nothing to flatten.
    static let levelBarHeight: CGFloat = 12
    /// Square floor for a level bar, so a near-zero length still leaves a mark.
    static let minimumLevelBarWidth: CGFloat = levelBarHeight
    /// Thickness range when a bar is weighted by value. The floor keeps a trivial holding visible;
    /// the ceiling stops one large group from dwarfing the rest of the list.
    static let weightedBarHeights: ClosedRange<CGFloat> = 4 ... 24

    /// Thickness for a group holding `share` of the largest group's value.
    static func weightedHeight(forShare share: Double) -> CGFloat {
        let span = weightedBarHeights.upperBound - weightedBarHeights.lowerBound
        let clamped = min(max(CGFloat(share), 0), 1)

        return weightedBarHeights.lowerBound + span * clamped
    }

    /// Kept to the same share of the height as ``solidBarCornerRadius`` is of ``barHeight``, so a
    /// floored level bar still reads as a rounded square rather than as a provenance circle.
    static let levelBarCornerRadius: CGFloat = 3
    static let outlineWidth: CGFloat = 1
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

    /// Frame drawn around every mark.
    ///
    /// The mark colours are semantic and pinned, so white has to stay white on a cream theme
    /// where it would otherwise vanish. A frame does that on its own — 18:1 against white, and
    /// 15:1 or better against every light surface — so the marks need no backdrop. On the dark
    /// theme it merges into the background, which costs nothing there: white already measures
    /// 19:1 against it.
    static let markFrame = Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255)
    static let markFrameWidth: CGFloat = 1

    /// Thinner, so the stacked pair keeps some colour inside its frame.
    static let thinFrameWidth: CGFloat = 0.75

    /// Lowest fungibility percentage in each bucket, most fungible first. Ratio is about 1.53 per
    /// step, so a bucket is roughly a one-and-a-half-fold change in the anonymity set, with the
    /// last two widened because scores that low are rare and not worth separating.
    private static let bucketFloors: [UInt8] = [66, 43, 28, 19, 12, 8, 5, 2, 0]

    /// Buckets run `0` (fully fungible, no bar) to ``maximumBucket`` (no anonymity, full column).
    static var maximumBucket: Int { bucketFloors.count - 1 }

    /// Buckets a fungibility percentage onto the log-ish ladder the bars are drawn in.
    ///
    /// Logarithmic rather than linear because the meaning of a difference is: going from being
    /// fungible with one other coin to four is substantial, going from 510 to 511 is not. Quantised
    /// because discrete lengths are what lets rows with the same standing collapse into one.
    static func bucket(forScore score: UInt8) -> Int {
        let clamped = min(score, CoinageConstants.fullFungibility)

        return bucketFloors.firstIndex { clamped >= $0 } ?? maximumBucket
    }

    /// Fraction of the column a bucket occupies.
    ///
    /// Inverted on purpose — a highly fungible holding draws a *short* bar, and a poorly fungible
    /// one stretches across the column.
    static func fraction(forBucket bucket: Int) -> CGFloat {
        let clamped = min(max(bucket, 0), maximumBucket)

        return CGFloat(clamped) / CGFloat(maximumBucket)
    }

    /// Penalty for a coin unloaded as one of a batch: the batch links it to the others that came
    /// out with it, which the recycler's own score does not account for.
    ///
    /// A flat step rather than `log(batch size)` because the batch size is not recorded. Two
    /// buckets is about a two-and-a-third-fold linkage, which understates a typical batch; it is a
    /// deliberate approximation, not an estimate.
    static let batchUnloadPenalty = 2

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
