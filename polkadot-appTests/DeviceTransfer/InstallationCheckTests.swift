@testable import polkadot_app
import AsyncExtensions
import Foundation
import StructuredConcurrencyTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct InstallationCheckTests {
    private let clock = ManualClock()
    private let retryDelay: Duration = .seconds(2)

    @Test("The connecting screen hands over to the root once a status settles, though only it keeps the root alive")
    func handsOverOnSettledStatus() async {
        let service = ScriptedInstallationService()
        let settled = DeviceSyncTestEventRecorder<Void>()
        let presenter = makeModule(service: service, observer: RootStateObserverSpy(settled: settled))

        presenter.setup()
        await service.waitForSetup()
        service.send(.unknown)
        service.send(.inactive(otherPhone))

        #expect(await settled.waitForCount(1).count == 1)
    }

    @Test("A configuration that can't be built yet is tried again after a delay instead of spinning forever")
    func failedConfigurationIsRetried() async {
        let service = ScriptedInstallationService()
        let settled = DeviceSyncTestEventRecorder<Void>()
        let presenter = makeModule(
            service: service,
            observer: RootStateObserverSpy(settled: settled),
            configurationFailures: 1
        )

        presenter.setup()
        await clock.resumeSleep(for: retryDelay)
        await service.waitForSetup()
        service.send(.active)

        #expect(await settled.waitForCount(1).count == 1)
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

    func makeModule(
        service: ScriptedInstallationService,
        observer: RootStateObserving,
        configurationFailures: Int = 0
    ) -> InstallationCheckPresenter {
        let interactor = InstallationCheckInteractor(
            serviceFactory: ScriptedInstallationServiceFactory(service: service, failures: configurationFailures),
            settings: InstallationCheckSettings(retryDelay: retryDelay, clock: clock),
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

private final class ScriptedInstallationServiceFactory: ActiveInstallationServiceMaking {
    struct ConfigurationError: Error {}

    private let service: ScriptedInstallationService
    private var failures: Int

    init(service: ScriptedInstallationService, failures: Int) {
        self.service = service
        self.failures = failures
    }

    func makeService() -> ActiveInstallationServicing {
        service
    }

    func makeConfiguration() throws -> ActiveInstallationConfiguration {
        guard failures == 0 else {
            failures -= 1
            throw ConfigurationError()
        }

        return ActiveInstallationConfiguration(
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

/// The test keeps only the recorder, like the scene delegate keeps nothing once the first route is shown.
@MainActor
private final class RootStateObserverSpy: RootStateObserving {
    private let settled: DeviceSyncTestEventRecorder<Void>

    init(settled: DeviceSyncTestEventRecorder<Void>) {
        self.settled = settled
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
    func didConfirmDeviceTransfer(_: DeviceTransferRequest) {}
}
