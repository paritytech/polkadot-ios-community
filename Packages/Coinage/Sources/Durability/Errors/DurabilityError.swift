import Foundation

/// Failures raised by the durability subsystem.
public enum DurabilityError: Error, Equatable {
    /// Registration rejected: the entry consumes nothing and mints nothing.
    case emptyEntry
    /// Registration rejected: an output is already an output, or a received-coin key, of
    /// another entry.
    case outputNotFresh(String)
    /// Registration rejected: an input is already claimed by an entry that is not a
    /// failure.
    case inputAlreadyClaimed(String)
    /// Registration rejected: an input carries a handoff mark.
    case inputHandedOff(String)
    /// The entry is not in the store.
    case entryNotFound(TransactionId)
    /// A pinned chain view could not be read, so the pass cannot run.
    case chainViewUnavailable
}
