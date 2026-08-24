import Foundation
import os

/// The set of entries a live submission currently owns.
///
/// Ownership is one-shot because there is exactly one acquisition site — `EntryRegistrar`, which
/// takes a freshly created entry id — and no path anywhere re-takes an id after release, including
/// after a resubmission. A recovery pass reads this per entry so an entry registered mid-pass is
/// skipped rather than judged on a chain view older than it is.
///
/// Synchronous by design: the pass must test membership without suspending between the test
/// and the read it guards.
public final class WatchedEntrySet: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Set<TransactionId>())

    public init() {}

    /// Takes ownership of an entry.
    public func take(_ id: TransactionId) {
        lock.withLock { watched in
            watched.insert(id)
        }
    }

    /// Releases ownership. Returns false if the entry was already released, so a caller can
    /// keep release side effects one-shot.
    @discardableResult
    public func release(_ id: TransactionId) -> Bool {
        lock.withLock { watched in
            watched.remove(id) != nil
        }
    }

    public func isWatched(_ id: TransactionId) -> Bool {
        lock.withLock { watched in watched.contains(id) }
    }
}
