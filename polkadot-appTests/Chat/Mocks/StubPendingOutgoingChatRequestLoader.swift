@testable import polkadot_app
import os

final class StubPendingOutgoingChatRequestLoader: PendingOutgoingChatRequestLoading, @unchecked Sendable {
    private let pending: OSAllocatedUnfairLock<PendingOutgoingRequest?>

    init(pending: PendingOutgoingRequest?) {
        self.pending = OSAllocatedUnfairLock(initialState: pending)
    }

    func setPending(_ pending: PendingOutgoingRequest?) {
        self.pending.withLock { $0 = pending }
    }

    func pendingRequest(requestId _: String) async throws -> PendingOutgoingRequest? {
        pending.withLock { $0 }
    }
}
