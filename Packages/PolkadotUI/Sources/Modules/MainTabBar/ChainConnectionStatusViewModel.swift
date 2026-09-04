import SwiftUI
import DesignSystem

public enum ChainConnectionState: Hashable {
    case connected
    case connecting
    case offline
}

public enum ChainStatusIcon: Hashable {
    case people
    case bulletin
    case assetHub
}

public struct ChainConnectionStatusViewModel: Hashable, Identifiable {
    public let id: String
    public let title: String
    public let state: ChainConnectionState
    public let stateTitle: String
    public let latency: Duration?
    public let lastBlockDate: Date?
    public let finalizedAdvancedAt: Date?
    public let connectedSince: Date?
    public let thresholds: ChainHealthThresholds
    public let icon: ChainStatusIcon

    public init(
        id: String,
        title: String,
        state: ChainConnectionState,
        stateTitle: String,
        latency: Duration?,
        lastBlockDate: Date?,
        finalizedAdvancedAt: Date?,
        connectedSince: Date?,
        thresholds: ChainHealthThresholds,
        icon: ChainStatusIcon
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.stateTitle = stateTitle
        self.latency = latency
        self.lastBlockDate = lastBlockDate
        self.finalizedAdvancedAt = finalizedAdvancedAt
        self.connectedSince = connectedSince
        self.thresholds = thresholds
        self.icon = icon
    }
}
