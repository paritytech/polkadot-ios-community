@testable import polkadot_app
import AsyncExtensions
import Foundation
import StatementStore
import SubstrateSdk
import SubstrateSdkExt
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ActiveInstallationServiceTests {
    private let store = MockStatementStore()
    private let schedule: DeviceTransferKeySchedule
    private let ownId = Data(repeating: 0x01, count: 32)
    private let otherId = Data(repeating: 0x02, count: 32)

    init() throws {
        schedule = try DeviceTransferKeySchedule(entropy: Data(repeating: 0x01, count: 16))
    }

    @Test("With no record on the topic, the installation publishes its own and becomes active")
    func firstInstallPublishesAndBecomesActive() async throws {
        let service = makeService(installationId: ownId)

        await service.setup(configuration: configuration())

        #expect(await waitForStatus(of: service) { $0 == .active } == .active)
        #expect(try storedRecords().map(\.installationId) == [ownId])
    }

    @Test("Another installation's record makes this one inactive without publishing")
    func otherRecordMakesInactive() async throws {
        let other = makeService(installationId: otherId)
        await other.setup(configuration: configuration())
        _ = await waitForStatus(of: other) { $0 == .active }

        let service = makeService(installationId: ownId)
        await service.setup(configuration: configuration())

        let status = await waitForStatus(of: service) { $0 != .unknown }
        #expect(try status == .inactive(#require(storedRecords().first)))
        #expect(try storedRecords().map(\.installationId) == [otherId])
    }

    @Test("An installation that finds its own record stays active and doesn't publish again")
    func ownRecordIsNotRepublished() async throws {
        let first = makeService(installationId: ownId)
        await first.setup(configuration: configuration())
        _ = await waitForStatus(of: first) { $0 == .active }
        await first.throttle()

        let restarted = makeService(installationId: ownId)
        await restarted.setup(configuration: configuration())

        #expect(await waitForStatus(of: restarted) { $0 != .unknown } == .active)
        #expect(try storedRecords().count == 1)
    }

    @Test("A record that can't be read makes the installation unreadable without publishing")
    func undecryptableRecordIsUnreadable() async throws {
        try store.insertStatement(with: makeBuilder(payload: Data([1, 2, 3])))
        let service = makeService(installationId: ownId)

        await service.setup(configuration: configuration())

        #expect(await waitForStatus(of: service) { $0 != .unknown } == .unreadable)
        #expect(try store.getStatements(with: topicFilter()).count == 1)
    }

    @Test("An unreachable store leaves the status unknown and publishes nothing")
    func unreachableStoreStaysUnknown() async throws {
        let connection = UnreachableStatementStore()
        let service = makeService(installationId: ownId)

        await service.setup(configuration: ActiveInstallationConfiguration(
            connection: connection,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
        ))
        await connection.waitForFetch()
        await service.throttle()

        #expect(await currentStatus(of: service) == .unknown)
        #expect(connection.submittedCount == 0)
    }

    @Test("A newer record from another phone turns the active installation inactive")
    func newerRecordTakesOver() async throws {
        let dates = MockDateProvider()
        let service = makeService(installationId: ownId, dates: dates)
        await service.setup(configuration: configuration())
        _ = await waitForStatus(of: service) { $0 == .active }

        await dates.advance(by: 10)
        let other = makeService(installationId: otherId, dates: dates)
        await other.setup(configuration: configuration())
        _ = await waitForStatus(of: other) { $0 != .unknown }
        try await other.publishSelf()

        let status = await waitForStatus(of: service) { $0 != .active }
        guard case let .inactive(record) = status else {
            Issue.record("Expected inactive, got \(status)")
            return
        }
        #expect(record.installationId == otherId)
    }

    @Test("An older record arriving late doesn't take the active status back")
    func olderRecordDoesNotWin() async throws {
        let dates = MockDateProvider()
        let late = makeService(installationId: otherId, dates: dates)
        await dates.advance(by: 10)
        let service = makeService(installationId: ownId, dates: dates)
        await service.setup(configuration: configuration())
        _ = await waitForStatus(of: service) { $0 == .active }

        await dates.advance(by: -5)
        await late.setup(configuration: configuration())
        _ = await waitForStatus(of: late) { $0 != .unknown }
        try await late.publishSelf()
        await service.throttle()

        let restarted = makeService(installationId: ownId, dates: dates)
        await restarted.setup(configuration: configuration())

        #expect(try storedRecords().count == 2)
        #expect(await waitForStatus(of: restarted) { $0 != .unknown } == .active)
    }

    @Test("Records activated at the same time go to the greater installation id")
    func tieGoesToGreaterInstallationId() async throws {
        let dates = MockDateProvider()
        let lower = makeService(installationId: ownId, dates: dates)
        let greater = makeService(installationId: otherId, dates: dates)
        await lower.setup(configuration: configuration())
        _ = await waitForStatus(of: lower) { $0 == .active }

        await greater.setup(configuration: configuration())
        _ = await waitForStatus(of: greater) { $0 != .unknown }
        try await greater.publishSelf()

        let status = await waitForStatus(of: lower) { $0 != .active }
        guard case let .inactive(record) = status else {
            Issue.record("Expected inactive, got \(status)")
            return
        }
        #expect(record.installationId == otherId)
    }
}

private extension ActiveInstallationServiceTests {
    func makeService(
        installationId: Data,
        dates: MockDateProvider = MockDateProvider()
    ) -> ActiveInstallationService {
        ActiveInstallationService(
            keyScheduleFactory: DeviceTransferKeyScheduleFactory(
                entropyManager: FixedRootEntropyManager(entropy: Data(repeating: 0x01, count: 16))
            ),
            installationProvider: FixedInstallationProvider(installationId: installationId),
            deviceInfo: DeviceInfo(model: "iPhone 17 Pro", operatingSystem: "iOS 26.1"),
            dateProvider: dates,
            logger: MockLogger()
        )
    }

    func configuration() -> ActiveInstallationConfiguration {
        ActiveInstallationConfiguration(
            connection: store,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
        )
    }

    func topicFilter() -> TopicFilter {
        .matchAll([schedule.activeDeviceTopic])
    }

    func makeBuilder(payload: Data) throws -> StatementSubmitParametersBuilder {
        try StatementSubmitParametersBuilder(
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
            logger: nil
        )
        .addTopic1(schedule.activeDeviceTopic)
        .addChannel(schedule.activeDeviceTopic)
        .addExpiry(1)
        .addScaleEncodedPayload(payload.scaleEncoded())
    }

    func storedRecords() throws -> [ActiveInstallation] {
        let cipher = ActiveInstallationRecordCipher(activeKey: schedule.activeKey)

        return try store.getStatements(with: topicFilter()).compactMap { encoded in
            let statement = try Statement.fromScaleEncoded(encoded)
            let payload = try #require(statement.getScaleEncodedPayload())
            return try cipher.open(Data.fromScaleEncoded(payload))
        }
    }

    func waitForStatus(
        of service: ActiveInstallationService,
        matching predicate: @escaping (InstallationStatus) -> Bool
    ) async -> InstallationStatus? {
        do {
            for try await status in await service.statusStream where predicate(status) {
                return status
            }
        } catch {
            Issue.record("Status stream failed: \(error)")
        }
        return nil
    }

    func currentStatus(of service: ActiveInstallationService) async -> InstallationStatus? {
        await waitForStatus(of: service) { _ in true }
    }
}

private struct FixedInstallationProvider: CurrentInstallationProviding {
    let installationId: Data

    func currentInstallationId() async throws -> Data {
        installationId
    }
}

private final class UnreachableStatementStore: StatementStoreConnecting, @unchecked Sendable {
    private let fetches = DeviceSyncTestEventRecorder<Void>()
    private let lock = NSLock()
    private var submits = 0

    var submittedCount: Int {
        lock.withLock { submits }
    }

    func waitForFetch() async {
        _ = await fetches.waitForCount(1)
    }

    func fetchStatements(with _: TopicFilter) async throws -> [Data] {
        fetches.record(())
        throw URLError(.notConnectedToInternet)
    }

    func subscribeStatements(with _: TopicFilter) throws -> AnyAsyncSequence<StatementsPage> {
        AsyncStream<StatementsPage> { _ in }.eraseToAnyAsyncSequence()
    }

    func submitStatement(with _: StatementSubmitParametersBuilding) async throws {
        lock.withLock { submits += 1 }
    }
}
