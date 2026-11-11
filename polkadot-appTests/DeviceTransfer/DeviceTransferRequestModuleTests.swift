@testable import polkadot_app
import AsyncExtensions
import Foundation
import PolkadotUI
import StatementStore
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct DeviceTransferRequestModuleTests {
    private let listener = ScriptedRequestListener()
    private let coordinator = RejectRecordingSenderCoordinator()
    private let view = RequestViewSpy()
    private let wireframe = RequestWireframeSpy()

    @Test("The sheet shows the requesting phone and follows a newer request")
    func sheetFollowsNewerRequest() async {
        let first = makeRequest(model: "iPhone 17 Pro")
        let newer = makeRequest(model: "iPhone 17 Air")
        listener.send(first)
        let presenter = makeModule(showing: first)
        presenter.setup()

        listener.send(newer)
        await view.waitForPhones(2)

        #expect(view.phones.map(\.model) == ["iPhone 17 Pro", "iPhone 17 Air"])
        #expect(wireframe.events.isEmpty)
        withExtendedLifetime(presenter) {}
    }

    @Test("A request withdrawn while the sheet is open closes it with a notice")
    func withdrawnRequestClosesWithNotice() async {
        let request = makeRequest(model: "iPhone 17 Pro")
        listener.send(request)
        let presenter = makeModule(showing: request)
        presenter.setup()

        listener.send(nil)
        await wireframe.waitForEvents(1)

        #expect(wireframe.events == [.closedAsWithdrawn])
        withExtendedLifetime(presenter) {}
    }

    @Test("Decline records the rejection and closes without a notice")
    func declineRejectsAndCloses() async {
        let request = makeRequest(model: "iPhone 17 Pro")
        listener.send(request)
        let presenter = makeModule(showing: request)
        presenter.setup()

        presenter.decline()
        await wireframe.waitForEvents(1)

        #expect(coordinator.rejected == [request])
        #expect(wireframe.events == [.closed])
    }

    @Test("Transfer hands the request to the root when no payment is pending")
    func transferConfirmsRequest() async {
        let request = makeRequest(model: "iPhone 17 Pro")
        listener.send(request)
        let presenter = makeModule(showing: request)
        presenter.setup()

        presenter.transfer()
        await wireframe.waitForEvents(1)

        #expect(wireframe.events == [.confirmed(request)])
    }

    @Test("Pending payments block the transfer: the sheet is shown and nothing is handed to the root")
    func pendingPaymentsBlockTransfer() async {
        let request = makeRequest(model: "iPhone 17 Pro")
        listener.send(request)
        let pending = PendingPayments(receiving: 1, sending: 2)
        let presenter = makeModule(showing: request, pendingPayments: .success(pending))
        presenter.setup()

        presenter.transfer()
        await wireframe.waitForEvents(1)
        presenter.transfer()
        await wireframe.waitForEvents(2)

        #expect(wireframe.events == [.blocked(pending), .blocked(pending)])
    }

    @Test("A count that can't be read doesn't hold the transfer back")
    func unreadableCountStillConfirms() async {
        let request = makeRequest(model: "iPhone 17 Pro")
        listener.send(request)
        let presenter = makeModule(showing: request, pendingPayments: .failure(CountError.unavailable))
        presenter.setup()

        presenter.transfer()
        await wireframe.waitForEvents(1)

        #expect(wireframe.events == [.confirmed(request)])
    }
}

private extension DeviceTransferRequestModuleTests {
    func makeRequest(model: String) -> DeviceTransferRequest {
        DeviceTransferRequest(
            requestId: UUID().uuidString,
            deviceModel: model,
            operatingSystem: "iOS 26.1",
            createdAt: 1
        )
    }

    func makeModule(
        showing request: DeviceTransferRequest,
        pendingPayments: Result<PendingPayments, Error> = .success(PendingPayments(receiving: 0, sending: 0))
    ) -> DeviceTransferRequestPresenter {
        let interactor = DeviceTransferRequestInteractor(
            listener: listener,
            servicesFactory: FixedSenderServicesFactory(coordinator: coordinator),
            paymentsCounter: FixedPaymentsCounter(result: pendingPayments),
            logger: MockLogger()
        )
        let presenter = DeviceTransferRequestPresenter(request: request, interactor: interactor, wireframe: wireframe)
        presenter.view = view
        interactor.presenter = presenter
        return presenter
    }
}

private final class ScriptedRequestListener: DeviceTransferRequestListening, @unchecked Sendable {
    private let subject = AsyncCurrentValueSubject<DeviceTransferRequest?>(nil)

    var pendingRequest: AnyAsyncSequence<DeviceTransferRequest?> {
        subject.eraseToAnyAsyncSequence()
    }

    func setup(connection _: StatementStoreConnecting) async {}
    func throttle() async {}

    func send(_ request: DeviceTransferRequest?) {
        subject.send(request)
    }
}

private enum CountError: Error {
    case unavailable
}

private struct FixedPaymentsCounter: PendingPaymentsCounting {
    let result: Result<PendingPayments, Error>

    func countPendingPayments() async throws -> PendingPayments {
        try result.get()
    }
}

private struct FixedSenderServicesFactory: DeviceTransferSenderServicesMaking {
    let coordinator: RejectRecordingSenderCoordinator

    func makeSenderServices() throws -> DeviceTransferSenderServices {
        DeviceTransferSenderServices(
            coordinator: coordinator,
            installationService: IdleInstallationService(),
            installationConfiguration: ActiveInstallationConfiguration(
                connection: MockStatementStore(),
                signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
            )
        )
    }
}

private struct IdleInstallationService: ActiveInstallationServicing {
    var statusStream: AnyAsyncSequence<InstallationStatus> {
        AsyncStream { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func setup(configuration _: ActiveInstallationConfiguration) async {}
    func throttle() async {}
    func publishSelf() async throws {}
}

private final class RejectRecordingSenderCoordinator: DeviceTransferSenderCoordinating, @unchecked Sendable {
    private let rejections = DeviceSyncTestEventRecorder<DeviceTransferRequest>()

    var rejected: [DeviceTransferRequest] { rejections.snapshot }

    var states: AnyAsyncSequence<DeviceTransferState> {
        AsyncCurrentValueSubject<DeviceTransferState>(.idle).eraseToAnyAsyncSequence()
    }

    func confirm(_: DeviceTransferRequest) async {}
    func cancel() async {}

    func reject(_ request: DeviceTransferRequest) async {
        rejections.record(request)
    }
}

@MainActor
private final class RequestViewSpy: UIViewController, DeviceTransferRequestViewProtocol {
    private let recorder = DeviceSyncTestEventRecorder<DeviceTransferPhone>()

    var phones: [DeviceTransferPhone] { recorder.snapshot }

    func didReceive(newPhone: DeviceTransferPhone) {
        recorder.record(newPhone)
    }

    func waitForPhones(_ count: Int) async {
        _ = await recorder.waitForCount(count)
    }
}

@MainActor
private final class RequestWireframeSpy: DeviceTransferRequestWireframeProtocol {
    enum Event: Equatable {
        case closed
        case closedAsWithdrawn
        case confirmed(DeviceTransferRequest)
        case blocked(PendingPayments)
    }

    private let recorder = DeviceSyncTestEventRecorder<Event>()

    var events: [Event] { recorder.snapshot }

    func close(from _: DeviceTransferRequestViewProtocol?) {
        recorder.record(.closed)
    }

    func closeAsWithdrawn(from _: DeviceTransferRequestViewProtocol?) {
        recorder.record(.closedAsWithdrawn)
    }

    func confirm(_ request: DeviceTransferRequest, from _: DeviceTransferRequestViewProtocol?) {
        recorder.record(.confirmed(request))
    }

    func showPendingPayments(_ payments: PendingPayments, from _: DeviceTransferRequestViewProtocol?) {
        recorder.record(.blocked(payments))
    }

    func waitForEvents(_ count: Int) async {
        _ = await recorder.waitForCount(count)
    }
}
