import Foundation
import IssueMonitoring

/// Failures that end a transfer badly with no short-term retry and would otherwise only reach the log.
struct DeviceTransferIssueDiagnostics: Sendable {
    /// A synced entity that failed to apply; the checkpoint moves past it, so it is never sent again.
    let entitySkipped: IssueDiagnostic
    /// Claim statuses whose message never arrived, dropped when the sender completes.
    let claimsDropped: IssueDiagnostic
    /// Connection attempts failing in a row without progress.
    let runStalled: IssueDiagnostic
}

extension DeviceTransferIssueDiagnostics {
    static func make(reporter: IssueReporting) -> Self {
        guard IssueMonitoringFactory.isReportingSupported else {
            return Self(
                entitySkipped: NoopIssueDiagnostic(),
                claimsDropped: NoopIssueDiagnostic(),
                runStalled: NoopIssueDiagnostic()
            )
        }

        return Self(
            entitySkipped: ThresholdIssueDiagnostic(
                flow: "device-transfer",
                kind: "entity-skipped",
                reporter: reporter
            ),
            claimsDropped: ThresholdIssueDiagnostic(
                flow: "device-transfer",
                kind: "claims-dropped",
                reporter: reporter
            ),
            runStalled: ThresholdIssueDiagnostic(
                flow: "device-transfer",
                kind: "run-stalled",
                threshold: 3,
                reporter: reporter
            )
        )
    }
}
