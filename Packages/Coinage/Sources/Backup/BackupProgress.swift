import Foundation

/// Where recovery of previous installations' balance stands. The initial pass runs on launch; a deep
/// search is the user asking for another look; `completed` is the user having accepted the balance.
public enum BackupProgress: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case syncing
        case completed
    }

    case unknown
    case initial(Phase)
    case deep(Phase)
    case completed

    public var isInProgress: Bool {
        switch self {
        case .initial(.syncing),
             .deep(.syncing): true
        case .unknown,
             .initial(.completed),
             .deep(.completed),
             .completed: false
        }
    }

    /// A recovered balance the user has not accepted yet.
    public var awaitsAcknowledgement: Bool {
        switch self {
        case .initial(.completed),
             .deep(.completed): true
        case .unknown,
             .initial(.syncing),
             .deep(.syncing),
             .completed: false
        }
    }
}

/// Whether the user has accepted the recovered balance. Persisted by the app; reset by the recovery
/// service whenever a scan finds a new installation, since new balance is worth another look.
public protocol DeepRecoveryCompletedStoring: Sendable {
    func isDeepRecoveryCompleted() async -> Bool
    func setDeepRecoveryCompleted(_ completed: Bool) async
}
