@testable import polkadot_app
import AsyncExtensions
import Foundation
import PolkadotUI
import StructuredConcurrencyTestSupport
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct DeviceTransferSenderModuleTests {
    private let order = DeviceSyncTestEventRecorder<String>()
    private let coordinator: ScriptedSenderCoordinator
    private let installationService = ScriptedSenderInstallationService()
    private let dashboardServices: DashboardResetSpy
    private let screenSleep = ScreenSleepSpy()
    private let view = SenderViewSpy()
    private let wireframe = SenderWireframeSpy()
    private let clock = ManualClock()
    private let handOverTimeout: Duration = .seconds(30)
    private let request = DeviceTransferRequest(
        requestId: "request",
        deviceModel: "iPhone 17 Pro",
        operatingSystem: "iOS 26.1",
        createdAt: 1
    )

    init() {
        coordinator = ScriptedSenderCoordinator(order: order)
        dashboardServices = DashboardResetSpy(order: order)
    }

    @Test("Screens follow the transfer, the screen stays on, and the module leaves once this phone is replaced")
    func screensFollowTransferUntilHandOver() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForConfirm()

        let steps: [(DeviceTransferState, DeviceTransferSenderScreen)] = [
            (.connecting, .connecting),
            (.syncing(applied: 1, total: 4), .sendingData(progress: 0.25)),
            (.reconnecting, .reconnecting(progress: 0.25)),
            (.syncing(applied: 4, total: 4), .sendingFiles),
            (.reconnecting, .reconnecting(progress: nil)),
            (.completed, .finishing)
        ]
        for (state, screen) in steps {
            coordinator.send(state)
            await view.waitFor(screen)
        }

        await installationService.waitForSetup()
        installationService.send(.inactive(newPhoneRecord))
        await wireframe.waitForEvents(1)

        #expect(order.snapshot == ["reset", "confirm"])
        #expect(view.screens == [.connecting] + steps.map(\.1).dropFirst())
        #expect(wireframe.events == [.complete])
        #expect(screenSleep.keptAwake.first == true)
        #expect(screenSleep.keptAwake.last == false)
    }

    @Test("Without the new phone's record, the module leaves once the hand-over timeout passes")
    func handOverTimesOut() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForConfirm()

        coordinator.send(.completed)
        await installationService.waitForSetup()
        await clock.resumeSleep(for: handOverTimeout)
        await wireframe.waitForEvents(1)

        #expect(wireframe.events == [.complete])
    }

    @Test("A cancel on the new phone shows its screen, and Back to chats leaves")
    func cancelOnNewPhoneShowsScreen() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForConfirm()

        coordinator.send(.failed(.aborted(.userCancelled)))
        await view.waitFor(.cancelledOnNewPhone)
        presenter.backToChats()

        #expect(wireframe.events == [.complete])
    }

    @Test("A failed transfer leaves with a notice")
    func failureLeavesWithNotice() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForConfirm()

        coordinator.send(.failed(.timedOut))
        await wireframe.waitForEvents(1)

        #expect(wireframe.events == [.completeAfterFailure])
    }

    @Test("Cancelling while data moves asks first, and only the confirm stops the run")
    func cancelDuringTransferAsksFirst() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForConfirm()
        coordinator.send(.syncing(applied: 1, total: 4))
        await view.waitFor(.sendingData(progress: 0.25))

        presenter.cancelTransfer()
        #expect(wireframe.events == [.confirmation])
        presenter.confirmCancelTransfer()

        await coordinator.waitForCancel()
    }

    @Test("Cancelling on this phone stops the run and leaves without a notice")
    func cancelHereLeavesQuietly() async {
        let presenter = makeModule()
        presenter.setup()
        await coordinator.waitForConfirm()

        presenter.cancelTransfer()
        await coordinator.waitForCancel()
        coordinator.send(.failed(.cancelled))
        await wireframe.waitForEvents(1)

        #expect(wireframe.events == [.complete])
    }
}

private extension DeviceTransferSenderModuleTests {
    var newPhoneRecord: ActiveInstallation {
        ActiveInstallation(
            installationId: Data(repeating: 0x02, count: 32),
            deviceModel: "iPhone 17 Pro",
            operatingSystem: "iOS 26.1",
            activatedAt: 1
        )
    }

    func makeModule() -> DeviceTransferSenderPresenter {
        let interactor = DeviceTransferSenderInteractor(
            servicesFactory: ScriptedSenderServicesFactory(
                coordinator: coordinator,
                installationService: installationService
            ),
            dashboardServices: dashboardServices,
            screenSleep: screenSleep,
            settings: DeviceTransferSenderModuleSettings(clock: clock, handOverTimeout: handOverTimeout),
            logger: MockLogger()
        )
        let presenter = DeviceTransferSenderPresenter(request: request, interactor: interactor, wireframe: wireframe)
        presenter.view = view
        interactor.presenter = presenter
        return presenter
    }
}

private struct ScriptedSenderServicesFactory: DeviceTransferSenderServicesMaking {
    let coordinator: ScriptedSenderCoordinator
    let installationService: ScriptedSenderInstallationService

    func makeSenderServices() throws -> DeviceTransferSenderServices {
        let configuration = ActiveInstallationConfiguration(
            connection: MockStatementStore(),
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
        )
        return DeviceTransferSenderServices(
            coordinator: coordinator,
            installationService: installationService,
            installationConfiguration: configuration
        )
    }
}

private final class ScriptedSenderCoordinator: DeviceTransferSenderCoordinating, @unchecked Sendable {
    private let subject = AsyncCurrentValueSubject<DeviceTransferState>(.idle)
    private let order: DeviceSyncTestEventRecorder<String>
    private let confirms = DeviceSyncTestEventRecorder<Void>()
    private let cancels = DeviceSyncTestEventRecorder<Void>()

    init(order: DeviceSyncTestEventRecorder<String>) {
        self.order = order
    }

    var states: AnyAsyncSequence<DeviceTransferState> {
        subject.eraseToAnyAsyncSequence()
    }

    func confirm(_: DeviceTransferRequest) async {
        order.record("confirm")
        confirms.record(())
    }

    func reject(_: DeviceTransferRequest) async {}

    func cancel() async {
        cancels.record(())
    }

    func send(_ state: DeviceTransferState) {
        subject.send(state)
    }

    func waitForConfirm() async {
        _ = await confirms.waitForCount(1)
    }

    func waitForCancel() async {
        _ = await cancels.waitForCount(1)
    }
}

private final class ScriptedSenderInstallationService: ActiveInstallationServicing, @unchecked Sendable {
    private let subject = AsyncCurrentValueSubject<InstallationStatus>(.active)
    private let setups = DeviceSyncTestEventRecorder<Void>()

    var statusStream: AnyAsyncSequence<InstallationStatus> {
        subject.eraseToAnyAsyncSequence()
    }

    func setup(configuration _: ActiveInstallationConfiguration) async {
        setups.record(())
    }

    func throttle() async {}
    func publishSelf() async throws {}

    func send(_ status: InstallationStatus) {
        subject.send(status)
    }

    func waitForSetup() async {
        _ = await setups.waitForCount(1)
    }
}

@MainActor
private final class DashboardResetSpy: DashboardServicesResetting {
    private let order: DeviceSyncTestEventRecorder<String>

    init(order: DeviceSyncTestEventRecorder<String>) {
        self.order = order
    }

    func reset() {
        order.record("reset")
    }
}

/// Records each screen once per change, the way the user sees them.
@MainActor
private final class SenderViewSpy: UIViewController, DeviceTransferSenderViewProtocol {
    private let recorder = DeviceSyncTestEventRecorder<DeviceTransferSenderScreen>()

    var screens: [DeviceTransferSenderScreen] { recorder.snapshot }

    func didReceive(screen: DeviceTransferSenderScreen, newPhone _: DeviceTransferPhone) {
        if recorder.snapshot.last != screen {
            recorder.record(screen)
        }
    }

    func waitFor(_ screen: DeviceTransferSenderScreen) async {
        var count = 1
        while await !(recorder.waitForCount(count).contains(screen)) {
            count += 1
        }
    }
}

@MainActor
private final class SenderWireframeSpy: DeviceTransferSenderWireframeProtocol {
    enum Event: Equatable {
        case complete
        case completeAfterFailure
        case confirmation
    }

    private let recorder = DeviceSyncTestEventRecorder<Event>()

    var events: [Event] { recorder.snapshot }

    func complete() {
        recorder.record(.complete)
    }

    func completeAfterFailure(from _: DeviceTransferSenderViewProtocol?) {
        recorder.record(.completeAfterFailure)
    }

    func showConfirmation(
        _: DeviceTransferConfirmationViewLayout.ViewModel,
        from _: DeviceTransferSenderViewProtocol?,
        onConfirm _: @escaping () -> Void
    ) {
        recorder.record(.confirmation)
    }

    func waitForEvents(_ count: Int) async {
        _ = await recorder.waitForCount(count)
    }
}
