import Foundation

@testable import polkadot_app

/// Passes every write through to the real store, keeping the incoming states written and yielding each
/// outgoing state as it is written.
final class RecordingTransferStateStore: TransferStateStoring, @unchecked Sendable {
    private let base: any TransferStateStoring
    private let lock = NSLock()
    private var recordedIncoming: [IncomingTransferState] = []
    let outgoingWrites: AsyncStream<OutgoingTransferState>
    private let outgoingContinuation: AsyncStream<OutgoingTransferState>.Continuation

    var incomingWrites: [IncomingTransferState] {
        lock.withLock { recordedIncoming }
    }

    init(base: any TransferStateStoring) {
        self.base = base
        (outgoingWrites, outgoingContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    func beginIncoming(messageId: Chat.MessageId) async throws -> Date {
        try await base.beginIncoming(messageId: messageId)
    }

    func updateIncoming(messageId: Chat.MessageId, state: IncomingTransferState) async throws {
        lock.withLock { recordedIncoming.append(state) }
        try await base.updateIncoming(messageId: messageId, state: state)
    }

    func updateOutgoing(messageId: Chat.MessageId, state: OutgoingTransferState) async throws {
        outgoingContinuation.yield(state)
        try await base.updateOutgoing(messageId: messageId, state: state)
    }
}
