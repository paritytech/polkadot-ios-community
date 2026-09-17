import Foundation
import Testing
@testable import polkadot_app

/// Geometry of the single voucher bar: total length, and how it splits between the ceiling head
/// and the barber pole.
@Suite("Voucher status bar layout")
struct VoucherStatusLayoutTests {
    private let column: CGFloat = 200
    private let minimum = CoinageStatusMetrics.minimumBarWidth
    private let worst = CoinageStatusMetrics.maximumBucket

    private func layout(max: Int, current: Int, width: CGFloat? = nil) -> VoucherStatusView.Layout {
        VoucherStatusView.layout(
            for: .init(maxBucket: max, bucket: current, isUnloadable: false),
            width: width ?? column
        )
    }

    // MARK: - Length

    @Test("Bar length is the bucket's share of the column")
    func lengthFollowsBucket() {
        // bucket 4 of 8
        #expect(layout(max: 4, current: 4).barWidth == 100)
    }

    @Test("A less fungible holding draws a longer bar")
    func worseBucketIsLonger() {
        #expect(layout(max: 0, current: 7).barWidth > layout(max: 0, current: 3).barWidth)
    }

    @Test("The worst bucket fills the column")
    func worstFillsColumn() {
        #expect(layout(max: 0, current: worst).barWidth == column)
    }

    @Test("Column narrower than the floor clamps to the column")
    func narrowColumn() {
        #expect(layout(max: 0, current: 0, width: 10).barWidth == 10)
    }

    // MARK: - The square floor

    @Test("A fully fungible holding is floored to a square")
    func floorApplies() {
        #expect(layout(max: 0, current: 0).barWidth == minimum)
    }

    // MARK: - The split

    @Test("A voucher already at its ceiling shows only the head")
    func atCeilingIsAllHead() {
        let result = layout(max: 3, current: 3)

        #expect(result.solidShare == 1)
    }

    @Test("A ring that can still reach full fungibility shows no head")
    func perfectCeilingHasNoHead() {
        #expect(layout(max: 0, current: 5).solidShare == 0)
    }

    @Test("Head takes the ceiling's share of the bar")
    func headShare() {
        // head 2/8, total 6/8
        let result = layout(max: 2, current: 6)

        #expect(abs(result.solidShare - 1.0 / 3) < 0.000_01)
    }

    /// The ceiling is frozen at ring entry while the current level keeps moving, so a later
    /// reading can invert the pair.
    @Test("An inverted pair clamps to all head instead of overrunning")
    func invertedPair() {
        let result = layout(max: 6, current: 2)

        #expect(result.solidShare == 1)
        #expect(result.barWidth == layout(max: 6, current: 6).barWidth)
    }

    // MARK: - Degenerate input

    @Test("Zero width yields no bar")
    func zeroWidth() {
        #expect(layout(max: 1, current: 4, width: 0).barWidth == 0)
    }
}
