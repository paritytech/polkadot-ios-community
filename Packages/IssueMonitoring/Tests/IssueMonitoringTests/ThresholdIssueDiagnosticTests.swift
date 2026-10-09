import os
import Testing
@testable import IssueMonitoring

struct ThresholdIssueDiagnosticTests {
    private let reporter = RecordingIssueReporter()

    @Test func reportsOnceWhenKeyReachesThreshold() {
        let diagnostic = makeDiagnostic(threshold: 3)

        for _ in 0 ..< 5 {
            diagnostic.recordFailure(for: "a", error: nil, counters: [:])
        }

        #expect(reporter.issues.map { $0.counters["failures"] } == [3])
    }

    @Test func countsEachKeySeparately() {
        let diagnostic = makeDiagnostic(threshold: 1)

        diagnostic.recordFailure(for: "a", error: nil, counters: [:])
        diagnostic.recordFailure(for: "a", error: nil, counters: [:])
        diagnostic.recordFailure(for: "b", error: nil, counters: [:])

        #expect(reporter.issues.count == 2)
    }

    @Test func recoveryStartsTheCountOver() {
        let diagnostic = makeDiagnostic(threshold: 2)

        diagnostic.recordFailure(for: "a", error: nil, counters: [:])
        diagnostic.recordRecovery(for: "a")
        diagnostic.recordFailure(for: "a", error: nil, counters: [:])

        #expect(reporter.issues.isEmpty)
    }

    @Test func sendsErrorTypeAndCountersButNotErrorText() {
        makeDiagnostic(threshold: 1).recordFailure(for: "a", error: TestError.secret("0xdead"), counters: ["size": 7])

        let issue = reporter.issues.first
        #expect(issue?.errorType?.hasSuffix("TestError") == true)
        #expect(issue?.counters == ["size": 7, "failures": 1])
        #expect(issue.map { "\($0)" }?.contains("0xdead") == false)
    }

    private func makeDiagnostic(threshold: Int) -> ThresholdIssueDiagnostic {
        ThresholdIssueDiagnostic(flow: "test", kind: "case", threshold: threshold, reporter: reporter)
    }
}

private enum TestError: Error {
    case secret(String)
}

private final class RecordingIssueReporter: IssueReporting, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<[CriticalIssue]>(initialState: [])

    var issues: [CriticalIssue] {
        state.withLock { $0 }
    }

    func report(_ issue: CriticalIssue) {
        state.withLock { $0.append(issue) }
    }
}
