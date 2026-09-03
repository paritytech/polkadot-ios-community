import Foundation

/// Lifecycle status of a durability entry.
///
/// `pending` and `pendingSuccess` are live — a recovery pass keeps evaluating them.
/// `finalizedSuccess` and `failure` are terminal and are never rewritten.
public enum CoinageTxStatus: Int, Sendable, Equatable {
    case pending = 0
    case pendingSuccess = 1
    case finalizedSuccess = 2
    case failure = 3
}

public extension CoinageTxStatus {
    /// Live transactions hold their inputs locked.
    var isLive: Bool {
        self == .pending || self == .pendingSuccess
    }

    /// * Executed in a block, finalized or not.
    /// *
    /// * The threshold to read on-chain presence against: a coin is only absent-because-consumed if whatever
    /// * minted it actually ran, and asking for finality there while presence is read at the best head reports
    /// * a coin that plainly existed a moment ago as one that may never have.
    var isArrived: Bool {
        self == .pendingSuccess || self == .finalizedSuccess
    }
}
