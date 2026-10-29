import Foundation
import AsyncExtensions
import FoundationExt
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import StructuredConcurrency
import SubstrateSdkExt

enum InstallationStatus: Equatable {
    /// The store wasn't read yet or was unreachable; callers keep the last known status.
    case unknown
    case active
    case inactive(ActiveInstallation)
    /// Records exist but none could be read: another key or an unknown version.
    case unreadable
}

struct ActiveInstallationConfiguration {
    let connection: StatementStoreConnecting
    let signer: StatementStoreSigning
}

protocol CurrentInstallationObserving: Sendable {
    var statusStream: AnyAsyncSequence<InstallationStatus> { get async }
}

protocol ActiveInstallationPublishing: Sendable {
    func publishSelf() async throws
}

protocol ActiveInstallationServicing: CurrentInstallationObserving, ActiveInstallationPublishing {
    func setup(configuration: ActiveInstallationConfiguration) async
    func throttle() async
}

enum ActiveInstallationServiceError: Error {
    case notConfigured
}

struct ActiveInstallationPublishSettings {
    let deviceInfo: DeviceInfo
    let priorityFactory: StatementPriorityMaking
    let firstInstallAttempts: Int
    let firstInstallRetryDelay: Duration

    init(
        deviceInfo: DeviceInfo,
        priorityFactory: StatementPriorityMaking = StatementPriorityFactory(),
        firstInstallAttempts: Int = 10,
        firstInstallRetryDelay: Duration = .seconds(1)
    ) {
        self.deviceInfo = deviceInfo
        self.priorityFactory = priorityFactory
        self.firstInstallAttempts = firstInstallAttempts
        self.firstInstallRetryDelay = firstInstallRetryDelay
    }
}

/// Follows the active installation record on `active_device_topic` and works out whether this installation is the
/// active one. It publishes its own record only when the topic holds none, never on a timer, so an old phone
/// coming online late can't take the active status back.
actor ActiveInstallationService {
    fileprivate struct Context {
        let configuration: ActiveInstallationConfiguration
        let topic: Data
        let cipher: ActiveInstallationRecordCipher
        let ownInstallationId: Data
    }

    private let keyScheduleFactory: DeviceTransferKeyScheduleMaking
    private let installationProvider: CurrentInstallationProviding
    private let publishSettings: ActiveInstallationPublishSettings
    private let dateProvider: any DateProviding
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
        dateProvider: any DateProviding = NowDateProvider(),
        logger: LoggerProtocol
    ) {
        self.keyScheduleFactory = keyScheduleFactory
        self.installationProvider = installationProvider
        self.publishSettings = publishSettings
        self.dateProvider = dateProvider
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

        let now = await dateProvider.read()
        let installation = ActiveInstallation(
            installationId: context.ownInstallationId,
            deviceModel: publishSettings.deviceInfo.model,
            operatingSystem: publishSettings.deviceInfo.operatingSystem,
            activatedAt: UInt64(now.timeIntervalSince1970.milliseconds)
        )

        let builder = try StatementSubmitParametersBuilder(signer: context.configuration.signer, logger: nil)
            .addTopic1(context.topic)
            .addChannel(context.topic)
            .addExpiry(publishSettings.priorityFactory.makeTimestampPriority())
            .addScaleEncodedPayload(context.cipher.seal(installation).scaleEncoded())

        try await context.configuration.connection.submitStatement(with: builder)

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
        }
    }

    func startFirstInstallDelivery() {
        let settings = publishSettings
        let logger = logger

        firstInstallTask = Task { [weak self] in
            do {
                try await withRetry(
                    maxAttempts: settings.firstInstallAttempts,
                    initialDelay: settings.firstInstallRetryDelay
                ) { [weak self] in
                    try await self?.deliverFirstInstall()
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to publish active installation record: \(error)")
            }
        }
    }

    /// A record that arrived while retrying means another installation got there first, so this one stays quiet.
    func deliverFirstInstall() async throws {
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
