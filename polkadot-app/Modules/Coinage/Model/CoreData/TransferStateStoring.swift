import Foundation

/// Lifecycle row of a chat coinage message; `CoinageTransferMonitor` is the only writer. A write that
/// changes nothing must not dirty the row, or every repeated status would refresh the message list.
protocol TransferStateStoring: Sendable {
    /// Fetch-or-insert as `detecting`; returns when this device first tried to claim, stable across calls.
    func beginIncoming(messageId: Chat.MessageId) async throws -> Date

    func updateIncoming(messageId: Chat.MessageId, state: IncomingTransferState) async throws

    /// As `updateIncoming`, for a state settled on a sibling device: it isn't marked modified, so device sync
    /// doesn't send it back.
    func applySyncedIncoming(messageId: Chat.MessageId, state: IncomingTransferState) async throws

    func updateOutgoing(messageId: Chat.MessageId, state: OutgoingTransferState) async throws
}
