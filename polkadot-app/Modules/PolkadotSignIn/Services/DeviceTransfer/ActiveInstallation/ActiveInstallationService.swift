import Foundation
import AsyncExtensions
import FoundationExt
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import StructuredConcurrency
import SubstrateSdkExt
import IssueMonitoring
import Individuality

struct ActiveInstallationConfiguration {
    let connection: StatementStoreConnecting
    let signer: StatementStoreSigning
    /// The lite person this seed registers as. Its ring inclusion is what lets the identity account take a
    /// statement-store slot, so a record submitted before it only collects `noAllowance` rejections.
    let lightPerson: any PersonStatusWaiting
}

protocol CurrentInstallationObserving: Sendable {
    var statusStream: AnyAsyncSequence<InstallationStatus> { get async }
}

protocol ActiveInstallationPublishing: Sendable {
    func publishSelf() async throws
}

struct ActiveInstallationPublishRetry {
    var attempts = 10
    var delay: Duration = .seconds(1)
}

extension ActiveInstallationPublishing {
    /// A missing configuration won't fix itself, so only submit failures are retried.
    func publishSelf(retry: ActiveInstallationPublishRetry) async throws {
        try await withRetry(
            maxAttempts: retry.attempts,
            initialDelay: retry.delay,
            shouldRetry: { !($0 is ActiveInstallationServiceError) },
            operation: { try await publishSelf() }
        )
    }
}

protocol ActiveInstallationServicing: CurrentInstallationObserving, ActiveInstallationPublishing {
    func setup(configuration: ActiveInstallationConfiguration) async
    func throttle() async
}

enum ActiveInstallationServiceError: Error {
    case notConfigured
}

struct ActiveInstallationPublishSettings {
    let deviceInfo: DeviceSystemInfo
    let priorityFactory: StatementPriorityMaking
    /// Stamps `activatedAt` on the published record.
    let dateProvider: any DateProviding
    /// The first-install publish keeps retrying while the service runs; the delay doubles up to the cap.
    let firstInstallRetryDelay: Duration
    let firstInstallMaxRetryDelay: Duration
    /// Reports a record that can't be followed, or a first-install publish still failing after many attempts.
    var stopDiagnostic: IssueDiagnostic = NoopIssueDiagnostic()
    var clock: any Clock<Duration> = ContinuousClock()

    init(
        deviceInfo: DeviceSystemInfo,
        priorityFactory: StatementPriorityMaking = StatementPriorityFactory(),
        dateProvider: any DateProviding = NowDateProvider(),
        firstInstallRetryDelay: Duration = .seconds(1),
        firstInstallMaxRetryDelay: Duration = .seconds(60)
    ) {
        self.deviceInfo = deviceInfo
        self.priorityFactory = priorityFactory
        self.dateProvider = dateProvider
        self.firstInstallRetryDelay = firstInstallRetryDelay
        self.firstInstallMaxRetryDelay = firstInstallMaxRetryDelay
    }
}

/// Follows the active installation record on `active_device_topic` and works out whether this installation is the
/// active one. It publishes its own record only when the topic holds none, never on a timer, so an old phone
/// coming online late can't take the active status back. An empty topic already makes this installation active:
/// the record only defends that claim against a phone arriving later, so publishing it waits for nobody.
actor ActiveInstallationService {
    private static let firstInstallFailuresBeforeDiagnostic = 10

    fileprivate struct Context {
        let configuration: ActiveInstallationConfiguration
        let topic: Data
        let cipher: ActiveInstallationRecordCipher
        let ownInstallationId: Data
    }

    private let keyScheduleFactory: DeviceTransferKeyScheduleMaking
    private let installationProvider: CurrentInstallationProviding
    private let publishSettings: ActiveInstallationPublishSettings
    private let statusStore: InstallationStatusStoring
    private let logger: LoggerProtocol

    private let statusSubject = AsyncCurrentValueSubject<InstallationStatus>(.unknown)
    private var context: Context?
    /// Only the newest readable record is kept, so statements flooding the topic can't grow memory.
    private var latestRecord: ActiveInstallation?
    private var hasUnreadableRecord = false
    private var followTask: Task<Void, Never>?
    private var firstInstallTask: Task<Void, Never>?

    init(
        keyScheduleFactory: DeviceTransferKeyScheduleMaking,
        installationProvider: CurrentInstallationProviding,
        publishSettings: ActiveInstallationPublishSettings,
        statusStore: InstallationStatusStoring,
        logger: LoggerProtocol
    ) {
        self.keyScheduleFactory = keyScheduleFactory
        self.installationProvider = installationProvider
        self.publishSettings = publishSettings
        self.statusStore = statusStore
        self.logger = logger
    }
}

extension ActiveInstallationService: ActiveInstallationServicing {
    var statusStream: AnyAsyncSequence<InstallationStatus> {
        statusSubject.eraseToAnyAsyncSequence()
    }

    func setup(configuration: ActiveInstallationConfiguration) async {
        await throttle()

        followTask = Task { [weak self] in
            await self?.run(configuration: configuration)
        }
    }

    func throttle() async {
        let tasks = [followTask, firstInstallTask]
        followTask = nil
        firstInstallTask = nil
        tasks.forEach { $0?.cancel() }
        for task in tasks {
            await task?.value
        }

        context = nil
        latestRecord = nil
        hasUnreadableRecord = false
    }

    func publishSelf() async throws {
        guard let context else {
            throw ActiveInstallationServiceError.notConfigured
        }

        let now = await publishSettings.dateProvider.read()
        let installation = ActiveInstallation(
            installationId: context.ownInstallationId,
            deviceModel: publishSettings.deviceInfo.model,
            operatingSystem: publishSettings.deviceInfo.operatingSystem,
            activatedAt: UInt64(now.timeIntervalSince1970.milliseconds)
        )

        let statement = try UnsignedStatement()
            .addTopic1(context.topic)
            .addChannel(context.topic)
            .addExpiry(publishSettings.priorityFactory.makeTimestampPriority())
            .addScaleEncodedPayload(context.cipher.seal(installation).scaleEncoded())

        let configuration = context.configuration
        try await configuration.connection.submitStatement(with: statement.signed(by: configuration.signer))

        remember(installation)
        evaluate()
    }
}

private extension ActiveInstallationService {
    func run(configuration: ActiveInstallationConfiguration) async {
        do {
            let schedule = try keyScheduleFactory.makeKeySchedule()
            let ownInstallationId = try await installationProvider.currentInstallationId()

            context = Context(
                configuration: configuration,
                topic: schedule.activeDeviceTopic,
                cipher: ActiveInstallationRecordCipher(activeKey: schedule.activeKey),
                ownInstallationId: ownInstallationId
            )

            try await follow(
                filter: TopicFilter.matchAll([schedule.activeDeviceTopic]),
                connection: configuration.connection
            )
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Active installation tracking stopped: \(error)")
            publishSettings.stopDiagnostic.recordFailure(for: "tracking", error: error, counters: [:])
        }
    }

    /// Unbounded: the identity account's allowance can wait on the person's registration for a long time.
    func startFirstInstallDelivery() {
        let settings = publishSettings
        let logger = logger

        firstInstallTask = Task { [weak self] in
            var delay = settings.firstInstallRetryDelay
            var failures = 0

            while !Task.isCancelled {
                do {
                    try await self?.deliverFirstInstall()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    failures += 1
                    logger.warning("Active installation record not published yet (\(failures)): \(error)")
                    if failures == Self.firstInstallFailuresBeforeDiagnostic {
                        settings.stopDiagnostic.recordFailure(
                            for: "first-install",
                            error: error,
                            counters: ["attempts": failures]
                        )
                    }
                    guard await (try? settings.clock.sleep(for: delay)) != nil else { return }
                    delay = min(delay * 2, settings.firstInstallMaxRetryDelay)
                }
            }
        }
    }

    /// A record that arrived meanwhile means another installation got there first, so this one stays quiet.
    func deliverFirstInstall() async throws {
        guard isTopicEmpty, let context else { return }

        try await context.configuration.lightPerson.waitUntilIncluded()
        guard isTopicEmpty else { return }

        try await publishSelf()
        logger.info("Published active installation record: no record existed")
    }

    var isTopicEmpty: Bool {
        latestRecord == nil && !hasUnreadableRecord
    }

    /// The subscription starts with the stored history and always ends it with a complete page, even an empty one,
    /// so the first complete page is where a first install is told apart from a known one.
    func follow(filter: TopicFilter, connection: StatementStoreConnecting) async throws {
        var isHistoryLoaded = false

        for try await page in try connection.subscribeStatements(with: filter) {
            try Task.checkCancellation()
            ingest(page.statements)

            if !isHistoryLoaded, page.isComplete {
                isHistoryLoaded = true

                if isTopicEmpty {
                    update(.active)
                    startFirstInstallDelivery()
                }
            }

            if isHistoryLoaded {
                evaluate()
            }
        }
    }

    func ingest(_ encodedStatements: [Data]) {
        guard let context else { return }

        for encoded in encodedStatements {
            if let installation = parse(encoded, cipher: context.cipher) {
                remember(installation)
            } else {
                hasUnreadableRecord = true
            }
        }
    }

    func parse(_ encoded: Data, cipher: ActiveInstallationRecordCipher) -> ActiveInstallation? {
        guard
            let statement = try? Statement.fromScaleEncoded(encoded),
            let payload = statement.getScaleEncodedPayload(),
            let sealed = try? Data.fromScaleEncoded(payload)
        else {
            return nil
        }

        return cipher.open(sealed)
    }

    func remember(_ installation: ActiveInstallation) {
        latestRecord = max(latestRecord ?? installation, installation)
    }

    func evaluate() {
        guard let context else { return }

        if let latestRecord {
            update(latestRecord.installationId == context.ownInstallationId ? .active : .inactive(latestRecord))
        } else if hasUnreadableRecord {
            update(.unreadable)
        }
    }

    func update(_ status: InstallationStatus) {
        guard statusSubject.value != status else { return }

        logger.info("Active installation status: \(status.logLabel)")
        // Saved first: whoever reacts to the new status reads the store, the root gate included.
        statusStore.save(status)
        statusSubject.send(status)
    }
}

private extension InstallationStatus {
    var logLabel: String {
        switch self {
        case .unknown: "unknown"
        case .active: "active"
        case .inactive: "inactive"
        case .unreadable: "unreadable"
        }
    }
}
