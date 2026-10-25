@testable import polkadot_app
import AsyncExtensions
import Foundation
import StatementStore
import SubstrateSdk
import SubstrateSdkExt
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferDiscoveryTests {
    private let store = MockStatementStore()
    private let dates = MockDateProvider()
    private let storage = UserDataStorageTestFacade()
    private let schedule: DeviceTransferKeySchedule

    init() throws {
        schedule = try DeviceTransferKeySchedule(entropy: Data(repeating: 0x01, count: 16))
    }

    @Test("Discovery messages keep their wire bytes")
    func wireBytes() throws {
        let request = DeviceTransferMessage.request(
            DeviceTransferRequest(requestId: "a", deviceModel: "b", operatingSystem: "c", createdAt: 1)
        )

        #expect(try request.scaleEncoded().toHex() == "00046104620463" + "0100000000000000")
        #expect(try DeviceTransferMessage.cancel(requestId: "a").scaleEncoded().toHex() == "010461")
    }

    @Test("A published request is offered to the active phone")
    func publishedRequestIsOffered() async throws {
        let request = try await makePublisher().publishRequest(configuration: configuration())
        let listener = try await makeListener()

        #expect(await waitForPending(of: listener) { $0 != nil } == request)
    }

    @Test("A cancel withdraws the offered request")
    func cancelWithdrawsRequest() async throws {
        let publisher = makePublisher()
        let request = try await publisher.publishRequest(configuration: configuration())
        let listener = try await makeListener()
        _ = await waitForPending(of: listener) { $0 != nil }

        try await publisher.cancel(requestId: request.requestId, configuration: configuration())

        #expect(await waitForPending(of: listener) { $0 == nil } == .some(nil))
    }

    @Test("Of several requests the newest is offered")
    func newestRequestWins() async throws {
        let publisher = makePublisher()
        _ = try await publisher.publishRequest(configuration: configuration())
        await dates.advance(by: 10)
        let newest = try await publisher.publishRequest(configuration: configuration())

        let listener = try await makeListener()

        #expect(await waitForPending(of: listener) { $0 != nil } == newest)
    }

    @Test("A request is withdrawn once its statement expires")
    func expiredStatementIsWithdrawn() async throws {
        let request = try await insertRequest(expiresIn: 60)
        let listener = try await makeListener()
        #expect(await waitForPending(of: listener) { $0 != nil } == request)

        await dates.advance(by: 61)
        try await insertUnrelatedCancel()

        #expect(await waitForPending(of: listener) { $0 == nil } == .some(nil))
    }

    @Test("A request is withdrawn once it is older than 15 minutes, though its statement is live")
    func oldRequestIsWithdrawn() async throws {
        let request = try await insertRequest(expiresIn: 30 * 60)
        let listener = try await makeListener()
        #expect(await waitForPending(of: listener) { $0 != nil } == request)

        await dates.advance(by: 15 * 60 + 1)
        try await insertUnrelatedCancel()

        #expect(await waitForPending(of: listener) { $0 == nil } == .some(nil))
    }

    @Test("A processed request isn't offered again after a relaunch")
    func processedRequestIsNotOfferedAgain() async throws {
        let publisher = makePublisher()
        let older = try await publisher.publishRequest(configuration: configuration())
        await dates.advance(by: 10)
        let processed = try await publisher.publishRequest(configuration: configuration())
        try await DeviceTransferProcessedCoreDataStore(storageFacade: storage)
            .markProcessed(requestId: processed.requestId.uppercased(), outcome: .rejected)

        let relaunched = try await makeListener()

        #expect(await waitForPending(of: relaunched) { $0 != nil } == older)
    }
}

private extension DeviceTransferDiscoveryTests {
    func configuration() -> DeviceTransferDiscoveryConfiguration {
        DeviceTransferDiscoveryConfiguration(
            connection: store,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
        )
    }

    func keyScheduleFactory() -> DeviceTransferKeyScheduleFactory {
        DeviceTransferKeyScheduleFactory(entropyManager: FixedRootEntropyManager(entropy: Data(
            repeating: 0x01,
            count: 16
        )))
    }

    func makePublisher() -> DeviceTransferRequestPublisher {
        DeviceTransferRequestPublisher(
            keyScheduleFactory: keyScheduleFactory(),
            deviceInfo: DeviceInfo(model: "iPhone 17 Pro", operatingSystem: "iOS 26.1"),
            dateProvider: dates
        )
    }

    func makeListener() async throws -> DeviceTransferRequestListener {
        let listener = DeviceTransferRequestListener(
            keyScheduleFactory: keyScheduleFactory(),
            processedStore: DeviceTransferProcessedCoreDataStore(storageFacade: storage),
            installationObserver: ActiveInstallationStub(),
            dateProvider: dates,
            logger: MockLogger()
        )
        await listener.setup(connection: store)
        return listener
    }

    func insertRequest(expiresIn lifetime: TimeInterval) async throws -> DeviceTransferRequest {
        let now = await dates.read()
        let request = DeviceTransferRequest(
            requestId: UUID().uuidString.lowercased(),
            deviceModel: "iPhone 16",
            operatingSystem: "iOS 26.0",
            createdAt: UInt64(now.timeIntervalSince1970.milliseconds)
        )
        try insert(.request(request), expiresAt: now.addingTimeInterval(lifetime))
        return request
    }

    /// Any new statement on the topic makes the listener re-evaluate what it offers.
    func insertUnrelatedCancel() async throws {
        try await insert(
            .cancel(requestId: UUID().uuidString.lowercased()),
            expiresAt: dates.read().addingTimeInterval(60)
        )
    }

    func insert(_ message: DeviceTransferMessage, expiresAt: Date) throws {
        let sealed = try DeviceTransferMessageCipher(requestKey: schedule.requestKey).seal(message)

        try store.insertStatement(
            with: StatementSubmitParametersBuilder(
                signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
                logger: nil
            )
            .addTopic1(schedule.requestTopic)
            .addChannel(schedule.requestTopic)
            .addExpiry(UInt64(expiresAt.timeIntervalSince1970) << 32)
            .addScaleEncodedPayload(sealed.scaleEncoded())
        )
    }

    func waitForPending(
        of listener: DeviceTransferRequestListener,
        matching predicate: @escaping (DeviceTransferRequest?) -> Bool
    ) async -> DeviceTransferRequest?? {
        do {
            for try await request in await listener.pendingRequest where predicate(request) {
                return .some(request)
            }
        } catch {
            Issue.record("Pending request stream failed: \(error)")
        }
        return .none
    }
}

private struct ActiveInstallationStub: CurrentInstallationObserving {
    var statusStream: AnyAsyncSequence<InstallationStatus> {
        AsyncCurrentValueSubject<InstallationStatus>(.active).eraseToAnyAsyncSequence()
    }
}
