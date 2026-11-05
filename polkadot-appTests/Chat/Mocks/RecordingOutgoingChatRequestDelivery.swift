@testable import polkadot_app
import Foundation
import os
import StatementDelivery
import StatementStore

final class RecordingOutgoingChatRequestDelivery: OutgoingStatementDelivering, @unchecked Sendable {
    private struct State {
        var retired: [String] = []
        var reinstated: [String] = []
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    var retired: [String] { state.withLock { $0.retired } }
    var reinstated: [String] { state.withLock { $0.reinstated } }

    func deliverUntilPublished(_: OutgoingChatRequestInput) async {}

    func deliverOnce(_: OutgoingChatRequestInput, signer _: StatementStoreSigning, period _: UInt32) async throws {}

    var onRetire: (() -> Void)?

    func retire(_ statementId: String) async {
        state.withLock { $0.retired.append(statementId) }
        onRetire?()
    }

    func reinstate(_ statementId: String) async {
        state.withLock { $0.reinstated.append(statementId) }
    }
}
