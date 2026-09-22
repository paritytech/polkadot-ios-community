import Foundation
@testable import polkadot_app

/// Records interactor output calls for testing Root setup behavior.
@MainActor
final class RootSetupOutputSpy: RootInteractorOutputProtocol {
    var didDecideCallCount = 0
    private(set) var failureKinds: [RootSetupFailureKind] = []

    var didFailSetupCallCount: Int { failureKinds.count }

    func didDecide(destination _: RootDestination) {
        didDecideCallCount += 1
    }

    func didFailSetup(kind: RootSetupFailureKind) {
        failureKinds.append(kind)
    }

    func didRequireAppFactoryReset() {}
}
