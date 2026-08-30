import Foundation

/// A durability entry's status write, applied atomically by
/// ``DurabilityStoring/compareAndSetStatus(_:observed:verdict:)``.
///
/// Mirrors Android's `Verdict`, with an explicit ``SuccessWrite`` for the recorded success block:
/// Android's nullable field only sets or clears, but iOS also needs "leave it untouched" so a
/// plain status change never disturbs the Rule 0 evidence it does not concern.
public struct Verdict: Sendable, Equatable {
    public let status: EntryStatus
    public let successDetectedAt: SuccessWrite

    public init(status: EntryStatus, successDetectedAt: SuccessWrite) {
        self.status = status
        self.successDetectedAt = successDetectedAt
    }
}

/// How a verdict touches the recorded `successDetectedAt` block.
public enum SuccessWrite: Sendable, Equatable {
    /// Leave the record as it is — a status change that does not concern the success block.
    case unchanged
    /// Clear the record — the entry has no observed success block.
    case clear
    /// Record this block as where execution was observed.
    case set(BlockRef)

    /// True when the verdict writes the record (sets or clears), as opposed to leaving it.
    public var touchesRecord: Bool {
        if case .unchanged = self { false } else { true }
    }

    /// The block a record-touching write stores: `nil` clears, a block sets. `nil` for `unchanged`
    /// too, so filter with ``touchesRecord`` before writing.
    public var block: BlockRef? {
        if case let .set(block) = self { block } else { nil }
    }
}
