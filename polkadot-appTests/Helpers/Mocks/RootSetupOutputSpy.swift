import Foundation
@testable import polkadot_app

/// Records interactor output calls for testing Root setup behavior.
@MainActor
final class RootSetupOutputSpy: RootInteractorOutputProtocol {
    var didDecideCallCount = 0
    var didFailSetupCallCount = 0

    func didDecide(destination _: RootDestination) {
        didDecideCallCount += 1
    }

    func didExceedSetupTimeout() {}

    func didFailSetup() {
        didFailSetupCallCount += 1
    }

    func didRequireAppFactoryReset() {}
}
