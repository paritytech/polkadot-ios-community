import Foundation
import AsyncExtensions
import FoundationExt
import MessageExchangeKit
import StatementStore
import SubstrateSdk
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

protocol ActiveInstallationServicing: Sendable {
    var statusStream: AnyAsyncSequence<InstallationStatus> { get async }

    func setup(configuration: ActiveInstallationConfiguration) async
    func throttle() async
    func publishSelf() async throws
}

enum ActiveInstallationServiceError: Error {
    case notConfigured
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

    fileprivate enum ParsedRecord {
        case readable(ActiveInstallation)
        case unreadable
    }

    private let keyScheduleFactory: DeviceTransferKeyScheduleMaking
    private let installationProvider: CurrentInstallationProviding
    private let deviceInfo: DeviceInfo
    private let dateProvider: any DateProviding
    private let priorityFactory: StatementPriorityMaking
    private let logger: LoggerProtocol

    private let statusSubject = AsyncCurrentValueSubject<InstallationStatus>(.unknown)
    private var context: Context?
    private var records: [Data: ParsedRecord] = [:]
    private var publishedRecord: ActiveInstallation?
    private var followTask: Task<Void, Never>?

    init(
        keyScheduleFactory: DeviceTransferKeyScheduleMaking,
        installationProvider: CurrentInstallationProviding,
        deviceInfo: DeviceInfo,
        dateProvider: any DateProviding = NowDateProvider(),
        priorityFactory: StatementPriorityMaking = StatementPriorityFactory(),
        logger: LoggerProtocol
    ) {
        self.keyScheduleFactory = keyScheduleFactory
        self.installationProvider = installationProvider
        self.deviceInfo = deviceInfo
        self.dateProvider = dateProvider
        self.priorityFactory = priorityFactory
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
        let task = followTask
        followTask = nil
        task?.cancel()
        await task?.value

        context = nil
        records = [:]
        publishedRecord = nil
    }

    func publishSelf() async throws {
        guard let context else {
            throw ActiveInstallationServiceError.notConfigured
        }

        let now = await dateProvider.read()
        let installation = ActiveInstallation(
            installationId: context.ownInstallationId,
            deviceModel: deviceInfo.model,
            operatingSystem: deviceInfo.operatingSystem,
            activatedAt: UInt64(now.timeIntervalSince1970.milliseconds)
        )

        let builder = try StatementSubmitParametersBuilder(signer: context.configuration.signer, logger: nil)
            .addTopic1(context.topic)
            .addChannel(context.topic)
            .addExpiry(priorityFactory.makeTimestampPriority())
            .addScaleEncodedPayload(context.cipher.seal(installation).scaleEncoded())

        try await context.configuration.connection.submitStatement(with: builder)

        publishedRecord = installation
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

    func publishAsFirstInstall() async {
        do {
            try await publishSelf()
            logger.info("Published active installation record: no record existed")
        } catch {
            logger.error("Failed to publish active installation record: \(error)")
        }
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

                if records.isEmpty {
                    await publishAsFirstInstall()
                }
            }

            if isHistoryLoaded {
                evaluate()
            }
        }
    }

    func ingest(_ encodedStatements: [Data]) {
        guard let context else { return }

        for encoded in encodedStatements where records[encoded] == nil {
            records[encoded] = parse(encoded, cipher: context.cipher)
        }
    }

    func parse(_ encoded: Data, cipher: ActiveInstallationRecordCipher) -> ParsedRecord {
        guard
            let statement = try? Statement.fromScaleEncoded(encoded),
            let payload = statement.getScaleEncodedPayload(),
            let sealed = try? Data.fromScaleEncoded(payload),
            let installation = cipher.open(sealed)
        else {
            return .unreadable
        }

        return .readable(installation)
    }

    func evaluate() {
        guard let context else { return }

        let readable = records.values.compactMap { record -> ActiveInstallation? in
            guard case let .readable(installation) = record else { return nil }
            return installation
        } + [publishedRecord].compactMap { $0 }

        guard let current = readable.max(by: Self.precedes) else {
            if !records.isEmpty {
                update(.unreadable)
            }
            return
        }

        update(current.installationId == context.ownInstallationId ? .active : .inactive(current))
    }

    func update(_ status: InstallationStatus) {
        guard statusSubject.value != status else { return }

        logger.info("Active installation status: \(status.logLabel)")
        statusSubject.send(status)
    }

    /// The current record has the greatest `activatedAt`; ties go to the greater installation id.
    static func precedes(_ lhs: ActiveInstallation, _ rhs: ActiveInstallation) -> Bool {
        if lhs.activatedAt != rhs.activatedAt {
            return lhs.activatedAt < rhs.activatedAt
        }

        return lhs.installationId.lexicographicallyPrecedes(rhs.installationId)
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
