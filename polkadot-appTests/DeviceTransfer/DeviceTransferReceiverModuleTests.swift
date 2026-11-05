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

    @Test("The screens follow the transfer, the bar keeps its value while reconnecting, and Continue leaves")
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

        #expect(view.oldPhone == DeviceTransferOldPhone(model: "iPhone 15", operatingSystem: "iOS 26.0"))
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

        presenter.activateWithoutTransfer()

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

        presenter.activateWithoutTransfer()
        await view.waitForAlert()

        #expect(installationService.publishCount == 3)
        #expect(view.alertMessages == [String(localized: .deviceTransferActivationFailed)])
        #expect(observer.settledCount == 0)
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

    func makeModule(saved: SavedInstallationStatus? = nil) -> DeviceTransferReceiverPresenter {
        let interactor = DeviceTransferReceiverInteractor(
            servicesFactory: ScriptedReceiverServicesFactory(
                coordinator: coordinator,
                installationService: installationService
            ),
            statusStore: FixedInstallationStatusStore(status: saved),
            clock: clock,
            publishRetry: ActiveInstallationPublishRetry(attempts: 3, delay: .zero),
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

private struct ScriptedReceiverServicesFactory: DeviceTransferReceiverServicesMaking {
    let coordinator: ScriptedReceiverCoordinator
    let installationService: PublishRecordingInstallationService

    func makeReceiverServices() throws -> DeviceTransferReceiverServices {
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
    var hasBeenActive: Bool { false }

    func save(_: InstallationStatus) {}
}

/// Records each screen once per change, the way the user sees them.
@MainActor
private final class ReceiverViewSpy: UIViewController, DeviceTransferReceiverViewProtocol {
    private let recorder = DeviceSyncTestEventRecorder<DeviceTransferReceiverScreen>()
    private let offerRecorder = DeviceSyncTestEventRecorder<Bool>()
    private let alertRecorder = DeviceSyncTestEventRecorder<String?>()
    private(set) var oldPhone: DeviceTransferOldPhone?

    var screens: [DeviceTransferReceiverScreen] { recorder.snapshot }
    var offers: [Bool] { offerRecorder.snapshot }
    var alertMessages: [String?] { alertRecorder.snapshot }

    override func present(_ controller: UIViewController, animated _: Bool, completion: (() -> Void)? = nil) {
        alertRecorder.record((controller as? UIAlertController)?.message)
        completion?()
    }

    func waitForAlert() async {
        _ = await alertRecorder.waitForCount(1)
    }

    func didReceive(screen: DeviceTransferReceiverScreen, oldPhone: DeviceTransferOldPhone?) {
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
}
