import Foundation

/// Represents the on-chain readiness state of a voucher for private transfers.
///
/// Readiness requires two conditions:
/// 1. Time condition: current time >= voucher.readyAt
/// 2. Ring size condition: recycler member count >= 10
public enum ReadinessState: Equatable {
    /// Time condition not yet met. Caller has voucher.readyAt for display.
    case waiting

    /// Time condition met AND ring size >= 10. Full privacy available.
    case ready

    /// Time condition met BUT ring size < 10
    case degraded(memberCount: Int)

    var readyOrDegraded: Bool {
        switch self {
        case .ready,
             .degraded: true
        case .waiting: false
        }
    }
}
