@testable import polkadot_app
import AsyncExtensions
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct InstallationCheckTests {
    @Test("The connecting screen hands over to the root once the service settles a status")
    func handsOverOnSettledStatus() async {
        let service = ScriptedInstallationService()
        let observer = RootStateObserverSpy()
        let presenter = makeModule(service: service, observer: observer)

        presenter.setup()
        await service.waitForSetup()
        service.send(.unknown)
        service.send(.inactive(otherPhone))

        await observer.waitForSettledStatus()
        #expect(observer.settledCount == 1)
    }
}

private extension InstallationCheckTests {
    var otherPhone: ActiveInstallation {
        ActiveInstallation(
            installationId: Data(repeating: 0x02, count: 32),
            deviceModel: "iPhone 17 Pro",
            operatingSystem: "iOS 26.1",
            activatedAt: 1
        )
    }

    func makeModule(service: ScriptedInstallationService, observer: RootStateObserving) -> InstallationCheckPresenter {
        let interactor = InstallationCheckInteractor(
            serviceFactory: ScriptedInstallationServiceFactory(service: service),
            logger: MockLogger()
        )
        let presenter = InstallationCheckPresenter(
            interactor: interactor,
            wireframe: InstallationCheckWireframe(observer: observer)
        )
        interactor.presenter = presenter
        return presenter
    }
}

private struct ScriptedInstallationServiceFactory: ActiveInstallationServiceMaking {
    let service: ScriptedInstallationService

    func makeService() -> ActiveInstallationServicing {
        service
    }

    func makeConfiguration() throws -> ActiveInstallationConfiguration {
        ActiveInstallationConfiguration(
            connection: MockStatementStore(),
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
        )
    }
}

private final class ScriptedInstallationService: ActiveInstallationServicing, @unchecked Sendable {
    private let subject = AsyncCurrentValueSubject<InstallationStatus>(.unknown)
    private let setups = DeviceSyncTestEventRecorder<Void>()

    var statusStream: AnyAsyncSequence<InstallationStatus> {
        subject.eraseToAnyAsyncSequence()
    }

    func setup(configuration _: ActiveInstallationConfiguration) async {
        setups.record(())
    }

    func throttle() async {}
    func publishSelf() async throws {}

    func waitForSetup() async {
        _ = await setups.waitForCount(1)
    }

    func send(_ status: InstallationStatus) {
        subject.send(status)
    }
}

@MainActor
private final class RootStateObserverSpy: RootStateObserving {
    private let settled = DeviceSyncTestEventRecorder<Void>()

    var settledCount: Int { settled.snapshot.count }

    func waitForSettledStatus() async {
        _ = await settled.waitForCount(1)
    }

    func didSettleInstallationStatus() {
        settled.record(())
    }

    func didCreateWallets() {}
    func didRestoreWallets() {}
    func didDecideBroken() {}
    func didClaimUsername() {}
    func didDecideClaim() {}
    func didSelectTheme() {}
}
