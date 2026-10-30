import Foundation
import os
import StatementStore

final class RecordingStatementStoreSubmitter: StatementStoreSubmitting, @unchecked Sendable {
    private struct State {
        var submitCount = 0
        var failures: [Error]
    }

    private let state: OSAllocatedUnfairLock<State>

    var submitCount: Int { state.withLock { $0.submitCount } }

    /// Each submit fails with the next queued error, then succeeds.
    init(failures: [Error] = []) {
        state = OSAllocatedUnfairLock(uncheckedState: State(failures: failures))
    }

    func submitStatement(with _: StatementSubmitParametersBuilding) async throws {
        let failure: Error? = state.withLock { state in
            state.submitCount += 1
            return state.failures.isEmpty ? nil : state.failures.removeFirst()
        }

        if let failure {
            throw failure
        }
    }
}
