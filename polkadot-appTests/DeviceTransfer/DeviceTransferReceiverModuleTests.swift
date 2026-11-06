@testable import polkadot_app
import AsyncExtensions
import Foundation
import PolkadotUI
import StructuredConcurrencyTestSupport
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct DeviceTransferReceiverModuleTests {
    private let coordinator = ScriptedReceiverCoordinator()
    private let view = ReceiverViewSpy()
    private let observer = ReceiverRootObserverSpy()
    private let installationService = PublishRecordingInstallationService()
    private let clock = ManualClock()
    private let screenSleep = ScreenSleepSpy()

    @Test("Screens follow the transfer, the bar holds while reconnecting, the screen stays on, Continue leaves")
    func screensFollowTransfer() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForSubscription()

        let steps: [(DeviceTransferState, DeviceTransferReceiverScreen)] = [
            (.waitingForSender, .waiting),
            (.connecting, .connecting),
            (.syncing(applied: 1, total: 2), .syncing(progress: 0.1)),
            (
                .files(DeviceTransferFileProgress(receivedBytes: 25, totalBytes: 100)),
                .files(progress: 0.4, receivedBytes: 25, totalBytes: 100)
            ),
            (.reconnecting, .reconnecting(progress: 0.4)),
            (.finalizing, .finishing),
            (.completed, .done)
        ]

        // The coordinator's subject keeps only its latest state, so each one is seen before the next is sent.
        for (state, screen) in steps {
            coordinator.send(state)
            await view.waitFor(screen)
        }
        presenter.complete()

        #expect(view.screens == [.start] + steps.map(\.1))
        #expect(observer.settledCount == 1)
        #expect(screenSleep.keptAwake.first == true)
        #expect(screenSleep.keptAwake.last == false)
    }

    @Test("Cancelling on this phone returns to the start, and the transfer can start again")
    func cancelReturnsToStart() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForSubscription()

        presenter.startTransfer()
        coordinator.send(.waitingForSender)
        await view.waitFor(.waiting)
        presenter.cancelTransfer()
        await coordinator.waitForCancel()
        coordinator.send(.failed(.cancelled))
        await view.waitFor(.start, occurrence: 2)
        presenter.startTransfer()

        await coordinator.waitForStarts(2)
    }

    @Test("A decline shows the declined screen with the old phone from the saved record")
    func declineShowsOldPhone() async {
        let presenter = makeModule(saved: .inactive(oldPhoneRecord))
        presenter.setup()
        await coordinator.waitForSubscription()

        coordinator.send(.failed(.rejected))
        await view.waitFor(.declined)

        #expect(view.oldPhone == DeviceTransferPhone(model: "iPhone 15", operatingSystem: "iOS 26.0"))
        #expect(view.offers == [true])
    }

    @Test("Waiting offers activating without the old phone only once five seconds pass")
    func waitingOffersActivationAfterDelay() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForSubscription()

        coordinator.send(.waitingForSender)
        await view.waitFor(.waiting)
        await clock.waitForSleep(for: .seconds(5))
        #expect(view.offers.isEmpty)

        await clock.resumeSleep(for: .seconds(5))
        await view.waitForOffers(1)

        #expect(view.offers == [true])
    }

    @Test("Activating without transfer withdraws the request, publishes this phone and leaves")
    func activationPublishesAndLeaves() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForSubscription()
        coordinator.send(.failed(.rejected))
        await view.waitFor(.declined)

        presenter.activateWithoutTransfer()
        #expect(view.confirmationCount == 1)
        presenter.confirmActivation()

        await coordinator.waitForCancel()
        await installationService.waitForPublish()
        await observer.waitForSettle()
    }

    @Test("A failed activation is retried, then reported in an alert, and the screen stays")
    func failedActivationRetriesThenAlerts() async {
        installationService.failsPublishing = true
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForSubscription()
        coordinator.send(.failed(.rejected))
        await view.waitFor(.declined)

        presenter.confirmActivation()
        await view.waitForAlert()

        #expect(installationService.publishCount == 3)
        #expect(view.alertMessages == [String(localized: .deviceTransferActivationFailed)])
        #expect(observer.settledCount == 0)
    }

    @Test("Services that couldn't be built when the screen opened are built again on Try again")
    func failedServicesAreRebuiltOnRetry() async {
        let presenter = makeModule(servicesFailures: 1)
        presenter.setup()
        await view.waitFor(.failed)

        presenter.startTransfer()

        await coordinator.waitForStarts(1)
    }

    @Test("Cancelling while data moves asks first, and only the confirm stops the run")
    func cancelDuringTransferAsksFirst() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForSubscription()
        coordinator.send(.syncing(applied: 1, total: 2))
        await view.waitFor(.syncing(progress: 0.1))

        presenter.cancelTransfer()
        #expect(view.confirmationCount == 1)
        presenter.confirmCancelTransfer()

        await coordinator.waitForCancel()
    }
}

private extension DeviceTransferReceiverModuleTests {
    var oldPhoneRecord: ActiveInstallation {
        ActiveInstallation(
            installationId: Data(repeating: 0x01, count: 32),
            deviceModel: "iPhone 15",
            operatingSystem: "iOS 26.0",
            activatedAt: 1
        )
    }

    func makeModule(
        saved: SavedInstallationStatus? = nil,
        servicesFailures: Int = 0
    ) -> DeviceTransferReceiverPresenter {
        let interactor = DeviceTransferReceiverInteractor(
            servicesFactory: ScriptedReceiverServicesFactory(
                coordinator: coordinator,
                installationService: installationService,
                failures: servicesFailures
            ),
            statusStore: FixedInstallationStatusStore(status: saved),
            screenSleep: screenSleep,
            settings: DeviceTransferReceiverModuleSettings(
                clock: clock,
                publishRetry: ActiveInstallationPublishRetry(attempts: 3, delay: .zero)
            ),
            logger: MockLogger()
        )
        let presenter = DeviceTransferReceiverPresenter(
            interactor: interactor,
            wireframe: DeviceTransferReceiverWireframe(observer: observer)
        )
        presenter.view = view
        interactor.presenter = presenter
        return presenter
    }
}

private final class ScriptedReceiverServicesFactory: DeviceTransferReceiverServicesMaking {
    struct BuildError: Error {}

    private let coordinator: ScriptedReceiverCoordinator
    private let installationService: PublishRecordingInstallationService
    private var failures: Int

    init(
        coordinator: ScriptedReceiverCoordinator,
        installationService: PublishRecordingInstallationService,
        failures: Int
    ) {
        self.coordinator = coordinator
        self.installationService = installationService
        self.failures = failures
    }

    func makeReceiverServices() throws -> DeviceTransferReceiverServices {
        guard failures == 0 else {
            failures -= 1
            throw BuildError()
        }

        let configuration = ActiveInstallationConfiguration(
            connection: MockStatementStore(),
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
        )
        return DeviceTransferReceiverServices(
            coordinator: coordinator,
            installationService: installationService,
            installationConfiguration: configuration,
            discoveryConfiguration: DeviceTransferDiscoveryConfiguration(
                connection: configuration.connection,
                signer: configuration.signer
            )
        )
    }
}

private final class ScriptedReceiverCoordinator: DeviceTransferReceiverCoordinating, @unchecked Sendable {
    private let subject = AsyncCurrentValueSubject<DeviceTransferState>(.idle)
    private let subscriptions = DeviceSyncTestEventRecorder<Void>()
    private let starts = DeviceSyncTestEventRecorder<Void>()
    private let cancels = DeviceSyncTestEventRecorder<Void>()

    var states: AnyAsyncSequence<DeviceTransferState> {
        get async {
            subscriptions.record(())
            return subject.eraseToAnyAsyncSequence()
        }
    }

    func start(configuration _: DeviceTransferDiscoveryConfiguration) async {
        starts.record(())
    }

    func cancel() async {
        cancels.record(())
    }

    func send(_ state: DeviceTransferState) {
        subject.send(state)
    }

    func waitForSubscription() async {
        _ = await subscriptions.waitForCount(1)
    }

    func waitForStarts(_ count: Int) async {
        _ = await starts.waitForCount(count)
    }

    func waitForCancel() async {
        _ = await cancels.waitForCount(1)
    }
}

private final class PublishRecordingInstallationService: ActiveInstallationServicing, @unchecked Sendable {
    private let publishes = DeviceSyncTestEventRecorder<Void>()
    var failsPublishing = false

    var publishCount: Int { publishes.snapshot.count }

    var statusStream: AnyAsyncSequence<InstallationStatus> {
        AsyncStream { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func setup(configuration _: ActiveInstallationConfiguration) async {}
    func throttle() async {}

    func publishSelf() async throws {
        publishes.record(())
        if failsPublishing {
            throw URLError(.notConnectedToInternet)
        }
    }

    func waitForPublish() async {
        _ = await publishes.waitForCount(1)
    }
}

private struct FixedInstallationStatusStore: InstallationStatusStoring {
    let status: SavedInstallationStatus?

    func save(_: InstallationStatus) {}
}

/// Records each screen once per change, the way the user sees them.
@MainActor
private final class ReceiverViewSpy: UIViewController, DeviceTransferReceiverViewProtocol {
    private let recorder = DeviceSyncTestEventRecorder<DeviceTransferReceiverScreen>()
    private let offerRecorder = DeviceSyncTestEventRecorder<Bool>()
    private let alertRecorder = DeviceSyncTestEventRecorder<String?>()
    private(set) var oldPhone: DeviceTransferPhone?

    var screens: [DeviceTransferReceiverScreen] { recorder.snapshot }
    var offers: [Bool] { offerRecorder.snapshot }
    var alertMessages: [String?] { alertRecorder.snapshot }

    private(set) var confirmationCount = 0

    override func present(_ controller: UIViewController, animated _: Bool, completion: (() -> Void)? = nil) {
        if let alert = controller as? UIAlertController {
            alertRecorder.record(alert.message)
        } else if controller is DeviceTransferConfirmationViewController {
            confirmationCount += 1
        }
        completion?()
    }

    func waitForAlert() async {
        _ = await alertRecorder.waitForCount(1)
    }

    func didReceive(screen: DeviceTransferReceiverScreen, oldPhone: DeviceTransferPhone?) {
        self.oldPhone = oldPhone
        if recorder.snapshot.last != screen {
            recorder.record(screen)
        }
    }

    func didReceive(offersActivation: Bool) {
        offerRecorder.record(offersActivation)
    }

    func waitForOffers(_ count: Int) async {
        _ = await offerRecorder.waitForCount(count)
    }

    func waitFor(_ screen: DeviceTransferReceiverScreen, occurrence: Int = 1) async {
        var seen = 0
        var count = 1
        while seen < occurrence {
            let screens = await recorder.waitForCount(count)
            seen = screens.filter { $0 == screen }.count
            count += 1
        }
    }
}

@MainActor
private final class ReceiverRootObserverSpy: RootStateObserving {
    private let settles = DeviceSyncTestEventRecorder<Void>()

    var settledCount: Int { settles.snapshot.count }

    func didSettleInstallationStatus() {
        settles.record(())
    }

    func waitForSettle() async {
        _ = await settles.waitForCount(1)
    }

    func didCreateWallets() {}
    func didRestoreWallets() {}
    func didDecideBroken() {}
    func didClaimUsername() {}
    func didDecideClaim() {}
    func didSelectTheme() {}
    func didConfirmDeviceTransfer(_: DeviceTransferRequest) {}
}
