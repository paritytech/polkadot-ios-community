import Foundation

/// Lifecycle status of a durability entry.
///
/// `pending` and `pendingSuccess` are live — a recovery pass keeps evaluating them.
/// `finalizedSuccess` and `failure` are terminal and are never rewritten.
public enum EntryStatus: Int, Sendable, Equatable {
    case pending = 0
    case pendingSuccess = 1
    case finalizedSuccess = 2
    case failure = 3
}

public extension EntryStatus {
    var isTerminal: Bool {
        self == .finalizedSuccess || self == .failure
    }

    var isLive: Bool {
        !isTerminal
    }
}
