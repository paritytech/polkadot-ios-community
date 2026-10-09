import IssueMonitoring
import os

final class RecordingIssueDiagnostic: IssueDiagnostic, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(failures: [String], recoveries: [String])>(initialState: ([], []))

    var failures: [String] {
        state.withLock { $0.failures }
    }

    var recoveries: [String] {
        state.withLock { $0.recoveries }
    }

    func recordFailure(for key: String, error _: Error?, counters _: [String: Int]) {
        state.withLock { $0.failures.append(key) }
    }

    func recordRecovery(for key: String) {
        state.withLock { $0.recoveries.append(key) }
    }
}
