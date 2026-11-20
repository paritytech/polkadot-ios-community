@testable import polkadot_app
import AsyncExtensions
import Foundation
import FoundationExt
import Individuality
import StatementStore
import StructuredConcurrencyTestSupport
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

    @Test("With no record on the topic the installation is active at once; its record lands once the lite person is in")
    func firstInstallIsActiveBeforeItsRecordLands() async throws {
        let waiter = ScriptedPersonStatusWaiter()
        let service = makeService(installationId: ownId)

        await service.setup(configuration: configuration(lightPerson: waiter))

        #expect(await waitForStatus(of: service) { $0 == .active } == .active)
        #expect(try storedRecords().isEmpty)

        waiter.include()
        try await waitForRecords(1)
        #expect(try storedRecords().map(\.installationId) == [ownId])
    }

    @Test("A failed first-install publish is retried past any fixed budget until it lands")
    func failedFirstInstallIsRetried() async throws {
        let connection = FlakySubmitStatementStore(store: store, failingSubmits: 12)
        let clock = ManualClock()
        let service = makeService(installationId: ownId, clock: clock)

        await service.setup(configuration: ActiveInstallationConfiguration(
            connection: connection,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
            lightPerson: IncludedPersonStatusWaiter()
        ))

        #expect(await waitForStatus(of: service) { $0 == .active } == .active)
        for _ in 0 ..< 12 {
            await clock.resumeSleep(for: .seconds(1))
        }
        try await waitForRecords(1)
        #expect(connection.submitAttempts == 13)
        #expect(try storedRecords().map(\.installationId) == [ownId])
    }

    @Test("A publish that keeps failing leaves the installation active and keeps trying")
    func failingPublishKeepsActive() async throws {
        let connection = FlakySubmitStatementStore(store: store, failingSubmits: .max)
        let clock = ManualClock()
        let service = makeService(installationId: ownId, clock: clock)

        await service.setup(configuration: ActiveInstallationConfiguration(
            connection: connection,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
            lightPerson: IncludedPersonStatusWaiter()
        ))

        #expect(await waitForStatus(of: service) { $0 == .active } == .active)
        for _ in 0 ..< 10 {
            await clock.resumeSleep(for: .seconds(1))
        }
        await clock.waitForSleep(for: .seconds(1))
        #expect(await currentStatus(of: service) == .active)
        #expect(connection.submitAttempts == 11)
        #expect(try storedRecords().isEmpty)
    }

    @Test("The first-install retry delay doubles up to the cap")
    func retryDelayDoublesUpToTheCap() async throws {
        let connection = FlakySubmitStatementStore(store: store, failingSubmits: .max)
        let clock = ManualClock()
        let service = makeService(installationId: ownId, clock: clock, maxRetryDelay: .seconds(4))

        await service.setup(configuration: ActiveInstallationConfiguration(
            connection: connection,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
            lightPerson: IncludedPersonStatusWaiter()
        ))

        await clock.resumeSleep(for: .seconds(1))
        await clock.resumeSleep(for: .seconds(2))
        await clock.resumeSleep(for: .seconds(4))
        await clock.waitForSleep(for: .seconds(4))
        #expect(connection.submitAttempts == 4)
    }

    @Test("Another phone's record arriving while the lite person is pending makes this one inactive and quiet")
    func otherRecordDuringPendingPersonStaysQuiet() async throws {
        let waiter = ScriptedPersonStatusWaiter()
        let connection = FlakySubmitStatementStore(store: store, failingSubmits: 0)
        let service = makeService(installationId: ownId)
        await service.setup(configuration: ActiveInstallationConfiguration(
            connection: connection,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
            lightPerson: waiter
        ))
        _ = await waitForStatus(of: service) { $0 == .active }

        let other = makeService(installationId: otherId)
        await other.setup(configuration: configuration())
        _ = await waitForStatus(of: other) { $0 == .active }
        let status = await waitForStatus(of: service) { $0 != .active }

        waiter.include()
        try await Task.sleep(for: .milliseconds(50))
        #expect(try status == .inactive(#require(storedRecords().first)))
        #expect(connection.submitAttempts == 0)
        #expect(try storedRecords().map(\.installationId) == [otherId])
    }

    @Test("Another installation's record makes this one inactive without publishing")
    func otherRecordMakesInactive() async throws {
        let other = makeService(installationId: otherId)
        await other.setup(configuration: configuration())
        _ = await waitForStatus(of: other) { $0 == .active }
        try await waitForRecords(1)

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
        try await waitForRecords(1)
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
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
            lightPerson: IncludedPersonStatusWaiter()
        ))
        await connection.waitForSubscription()
        await service.throttle()

        #expect(await currentStatus(of: service) == .unknown)
        #expect(connection.submittedCount == 0)
    }

    @Test("The status the service settles on is saved and read back after a relaunch")
    func settledStatusIsSaved() async throws {
        try await withSavedStatus { defaults in
            let dates = MockDateProvider()
            let ownStore = InstallationStatusStore(userDefaults: defaults, logger: MockLogger())
            let service = makeService(installationId: ownId, dates: dates, statusStore: ownStore)
            await service.setup(configuration: configuration())
            _ = await waitForStatus(of: service) { $0 == .active }
            try await waitForRecords(1)
            #expect(ownStore.status == .active)

            await dates.advance(by: 10)
            let other = makeService(installationId: otherId, dates: dates)
            await other.setup(configuration: configuration())
            _ = await waitForStatus(of: other) { $0 != .unknown }
            try await other.publishSelf()
            let status = await waitForStatus(of: service) { $0 != .active }

            let relaunched = InstallationStatusStore(userDefaults: defaults, logger: MockLogger())
            guard case let .inactive(record) = status else {
                Issue.record("Expected inactive, got \(String(describing: status))")
                return
            }
            #expect(relaunched.status == .inactive(record))
        }
    }

    @Test("An unreachable store keeps the status saved by an earlier launch")
    func unreachableStoreKeepsSavedStatus() async throws {
        try await withSavedStatus { defaults in
            let statusStore = InstallationStatusStore(userDefaults: defaults, logger: MockLogger())
            statusStore.save(.active)
            let connection = UnreachableStatementStore()
            let service = makeService(installationId: ownId, statusStore: statusStore)

            await service.setup(configuration: ActiveInstallationConfiguration(
                connection: connection,
                signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
                lightPerson: IncludedPersonStatusWaiter()
            ))
            await connection.waitForSubscription()
            await service.throttle()

            #expect(statusStore.status == .active)
        }
    }

    @Test("An empty first page of a longer history doesn't count as a first install")
    func incompleteHistoryIsNotAFirstInstall() async throws {
        let other = makeService(installationId: otherId)
        await other.setup(configuration: configuration())
        _ = await waitForStatus(of: other) { $0 == .active }
        try await waitForRecords(1)
        let connection = try PagedStatementStore(pages: [
            StatementsPage(statements: [], isComplete: false),
            StatementsPage(statements: store.getStatements(with: topicFilter()), isComplete: true)
        ])
        let service = makeService(installationId: ownId)

        await service.setup(configuration: ActiveInstallationConfiguration(
            connection: connection,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
            lightPerson: IncludedPersonStatusWaiter()
        ))

        let status = await waitForStatus(of: service) { $0 != .unknown }
        #expect(try status == .inactive(#require(storedRecords().first)))
        #expect(connection.submittedCount == 0)
    }

    @Test("A newer record from another phone turns the active installation inactive")
    func newerRecordTakesOver() async throws {
        let dates = MockDateProvider()
        let service = makeService(installationId: ownId, dates: dates)
        await service.setup(configuration: configuration())
        _ = await waitForStatus(of: service) { $0 == .active }
        try await waitForRecords(1)

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
        try await waitForRecords(1)

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
        try await waitForRecords(1)

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
        dates: MockDateProvider = MockDateProvider(),
        statusStore: InstallationStatusStoring = IgnoringInstallationStatusStore(),
        clock: ManualClock = ManualClock(),
        maxRetryDelay: Duration = .seconds(1)
    ) -> ActiveInstallationService {
        var publishSettings = ActiveInstallationPublishSettings(
            deviceInfo: DeviceSystemInfo(model: "iPhone 17 Pro", operatingSystem: "iOS 26.1"),
            dateProvider: dates,
            firstInstallRetryDelay: .seconds(1),
            firstInstallMaxRetryDelay: maxRetryDelay
        )
        publishSettings.clock = clock

        return ActiveInstallationService(
            keyScheduleFactory: DeviceTransferKeyScheduleFactory(
                entropyManager: FixedRootEntropyManager(entropy: Data(repeating: 0x01, count: 16))
            ),
            installationProvider: FixedInstallationProvider(installationId: installationId),
            publishSettings: publishSettings,
            statusStore: statusStore,
            logger: MockLogger()
        )
    }

    /// A store over a fresh defaults suite, removed again when `body` returns.
    func withSavedStatus(_ body: (UserDefaults) async throws -> Void) async throws {
        let suiteName = "ActiveInstallationServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try await body(defaults)
    }

    func configuration(
        lightPerson: any PersonStatusWaiting = IncludedPersonStatusWaiter()
    ) -> ActiveInstallationConfiguration {
        ActiveInstallationConfiguration(
            connection: store,
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32)),
            lightPerson: lightPerson
        )
    }

    func waitForRecords(_ count: Int) async throws {
        while try storedRecords().count < count {
            try await Task.sleep(for: .milliseconds(5))
        }
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
    private let subscriptions = DeviceSyncTestEventRecorder<Void>()
    private let lock = NSLock()
    private var submits = 0

    var submittedCount: Int {
        lock.withLock { submits }
    }

    func waitForSubscription() async {
        _ = await subscriptions.waitForCount(1)
    }

    func fetchStatements(with _: TopicFilter) async throws -> [Data] {
        throw URLError(.notConnectedToInternet)
    }

    func subscribeStatements(with _: TopicFilter) throws -> AnyAsyncSequence<StatementsPage> {
        subscriptions.record(())
        return AsyncThrowingStream<StatementsPage, Error> { $0.finish(throwing: URLError(.notConnectedToInternet)) }
            .eraseToAnyAsyncSequence()
    }

    func submitStatement(with _: StatementSubmitParametersBuilding) async throws {
        lock.withLock { submits += 1 }
    }
}

private final class PagedStatementStore: StatementStoreConnecting, @unchecked Sendable {
    private let pages: [StatementsPage]
    private let lock = NSLock()
    private var submits = 0

    init(pages: [StatementsPage]) {
        self.pages = pages
    }

    var submittedCount: Int {
        lock.withLock { submits }
    }

    func fetchStatements(with _: TopicFilter) async throws -> [Data] {
        []
    }

    func subscribeStatements(with _: TopicFilter) throws -> AnyAsyncSequence<StatementsPage> {
        AsyncStream<StatementsPage> { [pages] continuation in
            pages.forEach { continuation.yield($0) }
        }
        .eraseToAnyAsyncSequence()
    }

    func submitStatement(with _: StatementSubmitParametersBuilding) async throws {
        lock.withLock { submits += 1 }
    }
}

private final class FlakySubmitStatementStore: StatementStoreConnecting, @unchecked Sendable {
    private let store: MockStatementStore
    private let failingSubmits: Int
    private let lock = NSLock()
    private var attempts = 0

    init(store: MockStatementStore, failingSubmits: Int) {
        self.store = store
        self.failingSubmits = failingSubmits
    }

    var submitAttempts: Int {
        lock.withLock { attempts }
    }

    func fetchStatements(with filter: TopicFilter) async throws -> [Data] {
        try await store.fetchStatements(with: filter)
    }

    func subscribeStatements(with filter: TopicFilter) throws -> AnyAsyncSequence<StatementsPage> {
        store.subscribeStatements(with: filter)
    }

    func submitStatement(with builder: StatementSubmitParametersBuilding) async throws {
        let attempt = lock.withLock {
            attempts += 1
            return attempts
        }

        guard attempt > failingSubmits else {
            throw URLError(.timedOut)
        }

        try await store.submitStatement(with: builder)
    }
}

/// For tests that follow the live status only.
struct IgnoringInstallationStatusStore: InstallationStatusStoring {
    var status: SavedInstallationStatus? { nil }

    func save(_: InstallationStatus) {}
}
