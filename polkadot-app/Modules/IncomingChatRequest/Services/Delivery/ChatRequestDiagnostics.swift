import IssueMonitoring

struct ChatRequestDiagnostics {
    static let flow: StaticString = "chat-request"
    static let stalledDeliveryAttempts = 15
    static let failingRenewalRuns = 6

    let logger: LoggerProtocol
    let issueReporter: IssueReporting
}
