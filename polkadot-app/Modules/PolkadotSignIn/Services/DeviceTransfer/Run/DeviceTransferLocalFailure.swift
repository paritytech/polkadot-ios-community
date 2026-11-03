import Foundation
import IssueMonitoring

/// A step on this phone's own data failed; reconnecting resumes from the same checkpoint and fails the same way.
struct DeviceTransferLocalFailure: Error {
    let underlying: Error
}

enum DeviceTransferLocalFailureHandler {
    /// Marks a failure of `body` as local; cancellation and connection errors keep their meaning.
    static func withLocalFailure<Result>(_ body: () async throws -> Result) async throws -> Result {
        do {
            return try await body()
        } catch let error as CancellationError {
            throw error
        } catch let error as DeviceTransferRunError {
            throw error
        } catch {
            throw DeviceTransferLocalFailure(underlying: error)
        }
    }
}

extension DevicePeerConnectionFlowing {
    /// Ends the transfer on both phones instead of letting the context reconnect into the same failure.
    func abortOnLocalFailure(
        reportingTo diagnostic: IssueDiagnostic,
        as key: String,
        _ body: () async throws -> Void
    ) async throws {
        do {
            try await body()
        } catch let failure as DeviceTransferLocalFailure {
            diagnostic.recordFailure(for: key, error: failure.underlying, counters: [:])
            try? await sendTransferControl(.abort(.internalError))
            throw DeviceTransferRunError.aborted(.internalError)
        }
    }
}
