import Foundation

@testable import polkadot_app

/// For code paths that must finish before any product is resolved; reaching it fails the test run.
final class UnreachableFlowStateProvider: SPAFlowStateProviding {
    func flowState() -> SPAFlowState {
        preconditionFailure("Flow state must not be needed on this path")
    }
}
