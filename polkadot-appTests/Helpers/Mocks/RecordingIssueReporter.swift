import IssueMonitoring
import os

final class RecordingIssueReporter: IssueReporting, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<[CriticalIssue]>(initialState: [])

    var kinds: [String] {
        state.withLock { $0.map(\.kind) }
    }

    func report(_ issue: CriticalIssue, onceFor _: String) {
        state.withLock { $0.append(issue) }
    }
}
