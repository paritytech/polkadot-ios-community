import Foundation
import SwiftUI
import DesignSystem

public struct ChainHealthBounds: Hashable {
    public let healthy: Duration
    public let zero: Duration

    public init(healthy: Duration, zero: Duration) {
        self.healthy = healthy
        self.zero = zero
    }
}

public struct ChainHealthThresholds: Hashable {
    public let blockAge: ChainHealthBounds
    public let finalityStall: ChainHealthBounds
    public let ping: ChainHealthBounds
    public let missingTermGrace: Duration

    public init(
        blockAge: ChainHealthBounds,
        finalityStall: ChainHealthBounds,
        ping: ChainHealthBounds,
        missingTermGrace: Duration
    ) {
        self.blockAge = blockAge
        self.finalityStall = finalityStall
        self.ping = ping
        self.missingTermGrace = missingTermGrace
    }
}

enum ChainHealth {
    static func score(for viewModel: ChainConnectionStatusViewModel, at date: Date) -> Double {
        guard viewModel.state == .connected else {
            return 0
        }

        let thresholds = viewModel.thresholds

        // Compute the three health terms.
        let blockAgeTerm = elapsedScore(since: viewModel.lastBlockDate, at: date, bounds: thresholds.blockAge)
        let finalityStallTerm = elapsedScore(
            since: viewModel.finalizedAdvancedAt,
            at: date,
            bounds: thresholds.finalityStall
        )
        let pingTerm = viewModel.latency.map { linearScore($0.timeInterval, within: thresholds.ping) }

        // Grace period: while within missingTermGrace of connection, omit nil terms.
        // After grace expires, nil terms become 0.
        // Nil connectedSince while connected is treated as grace-expired.
        let inGrace: Bool =
            if let connectedSinceDate = viewModel.connectedSince {
                date.timeIntervalSince(connectedSinceDate) < thresholds.missingTermGrace.timeInterval
            } else {
                false
            }

        let terms: [Double?] = [blockAgeTerm, finalityStallTerm, pingTerm]
        let scoredTerms = inGrace
            ? terms.compactMap { $0 }
            : terms.map { $0 ?? 0 }

        return scoredTerms.min() ?? 0
    }
}

private extension ChainHealth {
    static func elapsedScore(since date: Date?, at now: Date, bounds: ChainHealthBounds) -> Double? {
        guard let date else {
            return nil
        }

        return linearScore(now.timeIntervalSince(date), within: bounds)
    }

    // Linear scoring: full health at or below `healthy`, 0 at or above `zero`, linear between.
    static func linearScore(_ elapsed: TimeInterval, within bounds: ChainHealthBounds) -> Double {
        let healthy = bounds.healthy.timeInterval
        let zero = bounds.zero.timeInterval

        if elapsed <= healthy {
            return 1
        } else if elapsed >= zero {
            return 0
        } else {
            return 1 - (elapsed - healthy) / (zero - healthy)
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
