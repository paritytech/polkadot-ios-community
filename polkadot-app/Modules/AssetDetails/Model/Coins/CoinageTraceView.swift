import DesignSystem
import PolkadotUI
import SwiftUI

/// What a picked-out coin says about itself, beside it in the band: its value and whether it is
/// Ready or Clearing, its hops since it last cleared, and how well it cleared.
struct CoinageTraceView: View {
    let trace: CoinageCoinTrace

    private static let headline: CGFloat = 30
    private static let line: CGFloat = 18
    private static let inset: CGFloat = CoinageArrangement.focusInset

    /// How tall the band has to be for the trace to fit beside the coin. Always the same two
    /// lines under the headline, so it is the coin's own height that decides.
    static func height(for _: CoinageCoinTrace) -> CGFloat {
        max(CoinageArrangement.focusBandMinimum, inset * 2 + headline + line * 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacings.extraSmall) {
                Text(trace.value)
                    .typography(.titleLarge)
                    .foregroundStyle(Color.fgPrimary)

                Text(String(localized: trace.partition == .ready ? .coinageSpendable : .coinageLoading))
                    .typography(.bodySmall)
                    .foregroundStyle(Color.fgSecondary)
            }
            .frame(height: Self.headline)

            line(String(localized: .coinageTraceHops(trace.hops)))
            line(String(localized: .coinageTraceQuality(Self.grade(trace.quality))))
        }
        .padding(.vertical, Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .typography(.bodySmall)
            .foregroundStyle(Color.fgSecondary)
            .lineLimit(1)
            .frame(height: Self.line)
    }

    private static func grade(_ quality: CoinageCoinTrace.Quality) -> String {
        switch quality {
        case .unknown: String(localized: .coinageTraceQualityUnknown)
        case .veryLow: String(localized: .coinageTraceQualityVeryLow)
        case .low: String(localized: .coinageTraceQualityLow)
        case .fair: String(localized: .coinageTraceQualityFair)
        case .good: String(localized: .coinageTraceQualityGood)
        case .high: String(localized: .coinageTraceQualityHigh)
        }
    }
}
