import Foundation
import IssueMonitoring

/// Failures that end a transfer badly with no short-term retry and would otherwise only reach the log.
struct DeviceTransferIssueDiagnostics: Sendable {
    /// A synced entity that failed to apply; the checkpoint moves past it, so it is never sent again.
    let entitySkipped: IssueDiagnostic
    /// Claim statuses whose message never arrived, dropped when the sender completes.
    let claimsDropped: IssueDiagnostic
    /// Connection attempts failing in a row before the channel opens; the run gives up a little later.
    let connectionFailed: IssueDiagnostic
    /// A step on this phone's own data failed, so the transfer was aborted on both phones.
    let dataFailed: IssueDiagnostic
    /// The installation record can't be published or followed, so the status stays unknown until a relaunch.
    let installationStopped: IssueDiagnostic
    /// Transfer services or their configuration can't be built.
    let setupFailed: IssueDiagnostic
    /// Transfer requests stop being followed until the next start.
    let listenerStopped: IssueDiagnostic
    /// The new phone's record couldn't be published after every retry.
    let finalizePublishFailed: IssueDiagnostic
}

extension DeviceTransferIssueDiagnostics {
    static func make(reporter: IssueReporting) -> Self {
        guard IssueMonitoringFactory.isReportingSupported else {
            return Self(
                entitySkipped: NoopIssueDiagnostic(),
                claimsDropped: NoopIssueDiagnostic(),
                connectionFailed: NoopIssueDiagnostic(),
                dataFailed: NoopIssueDiagnostic(),
                installationStopped: NoopIssueDiagnostic(),
                setupFailed: NoopIssueDiagnostic(),
                listenerStopped: NoopIssueDiagnostic(),
                finalizePublishFailed: NoopIssueDiagnostic()
            )
        }

        return Self(
            entitySkipped: diagnostic("entity-skipped", reporter: reporter),
            claimsDropped: diagnostic("claims-dropped", reporter: reporter),
            connectionFailed: diagnostic("connection-failed", threshold: 3, reporter: reporter),
            dataFailed: diagnostic("data-failed", reporter: reporter),
            installationStopped: diagnostic("installation-stopped", reporter: reporter),
            setupFailed: diagnostic("setup-failed", reporter: reporter),
            listenerStopped: diagnostic("listener-stopped", reporter: reporter),
            finalizePublishFailed: diagnostic("finalize-publish-failed", reporter: reporter)
        )
    }

    static func makeDefault() -> Self {
        make(reporter: IssueReportingFacade.shared)
    }
}

private extension DeviceTransferIssueDiagnostics {
    static func diagnostic(_ kind: StaticString, threshold: Int = 1, reporter: IssueReporting) -> IssueDiagnostic {
        ThresholdIssueDiagnostic(flow: "device-transfer", kind: kind, threshold: threshold, reporter: reporter)
    }
}
