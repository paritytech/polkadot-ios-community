import Foundation
import AsyncAlgorithms
import AsyncExtensions
import FoundationExt
import StatementStore
import SubstrateSdk
import SubstrateSdkExt

protocol DeviceTransferRequestListening: Sendable {
    var pendingRequest: AnyAsyncSequence<DeviceTransferRequest?> { get async }

    func setup(connection: StatementStoreConnecting) async
    func throttle() async
}

/// The active phone's side of discovery. It follows `request_topic` only while `eligibility` is true and offers the
/// newest request that hasn't expired, isn't older than 15 minutes, wasn't cancelled and wasn't processed.
actor DeviceTransferRequestListener {
    fileprivate struct ReceivedStatement {
        let message: DeviceTransferMessage?
        let expiresAt: UInt64
    }

    private let keyScheduleFactory: DeviceTransferKeyScheduleMaking
    private let processedStore: DeviceTransferProcessedStoring
    private let eligibility: AnyAsyncSequence<Bool>
    private let dateProvider: any DateProviding
    private let logger: LoggerProtocol

    private let subject = AsyncCurrentValueSubject<DeviceTransferRequest?>(nil)
    private var runTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    private var received: [Data: ReceivedStatement] = [:]

    init(
        keyScheduleFactory: DeviceTransferKeyScheduleMaking,
        processedStore: DeviceTransferProcessedStoring,
        eligibility: AnyAsyncSequence<Bool>,
        dateProvider: any DateProviding = NowDateProvider(),
        logger: LoggerProtocol
    ) {
        self.keyScheduleFactory = keyScheduleFactory
        self.processedStore = processedStore
        self.eligibility = eligibility
        self.dateProvider = dateProvider
        self.logger = logger
    }

    /// Listening is allowed only on the active installation with its main screen in front (RFC §5).
    static func eligibility(
        installationStatus: AnyAsyncSequence<InstallationStatus>,
        mainScreenVisibility: AnyAsyncSequence<Bool>
    ) -> AnyAsyncSequence<Bool> {
        combineLatest(installationStatus, mainScreenVisibility)
            .map { status, isVisible in status == .active && isVisible }
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }
}

extension DeviceTransferRequestListener: DeviceTransferRequestListening {
    var pendingRequest: AnyAsyncSequence<DeviceTransferRequest?> {
        subject.eraseToAnyAsyncSequence()
    }

    func setup(connection: StatementStoreConnecting) async {
        await throttle()

        runTask = Task { [weak self] in
            await self?.run(connection: connection)
        }
    }

    func throttle() async {
        let task = runTask
        runTask = nil
        task?.cancel()
        await task?.value

        await stopFollowing()
    }
}

private extension DeviceTransferRequestListener {
    func run(connection: StatementStoreConnecting) async {
        do {
            for try await isEligible in eligibility {
                try Task.checkCancellation()
                await stopFollowing()

                if isEligible {
                    startFollowing(connection: connection)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Device transfer eligibility stream failed: \(error)")
        }
    }

    func startFollowing(connection: StatementStoreConnecting) {
        followTask = Task { [weak self] in
            await self?.follow(connection: connection)
        }
    }

    func stopFollowing() async {
        let task = followTask
        followTask = nil
        task?.cancel()
        await task?.value

        received = [:]
        update(nil)
    }

    func follow(connection: StatementStoreConnecting) async {
        do {
            let schedule = try keyScheduleFactory.makeKeySchedule()
            let cipher = DeviceTransferMessageCipher(requestKey: schedule.requestKey)
            let filter = TopicFilter.matchAll([schedule.requestTopic])

            for try await page in try connection.subscribeStatements(with: filter) {
                try Task.checkCancellation()
                try await ingest(page.statements, cipher: cipher)
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Device transfer request listening stopped: \(error)")
        }
    }

    func ingest(_ encodedStatements: [Data], cipher: DeviceTransferMessageCipher) async throws {
        for encoded in encodedStatements where received[encoded] == nil {
            received[encoded] = parse(encoded, cipher: cipher)
        }

        try await evaluate()
    }

    func parse(_ encoded: Data, cipher: DeviceTransferMessageCipher) -> ReceivedStatement? {
        guard
            let statement = try? Statement.fromScaleEncoded(encoded),
            let expiry = statement.getExpiry(),
            let payload = statement.getScaleEncodedPayload(),
            let sealed = try? Data.fromScaleEncoded(payload)
        else {
            return nil
        }

        return ReceivedStatement(message: try? cipher.open(sealed), expiresAt: expiry >> 32)
    }

    func evaluate() async throws {
        let now = await dateProvider.read()
        let liveRequests = liveRequests(at: now)
        let processed = try await processedStore.processedRequestIds(among: liveRequests.map(\.requestId))

        try Task.checkCancellation()

        let newest = liveRequests
            .filter { !processed.contains($0.requestId.lowercased()) }
            .max { $0.createdAt < $1.createdAt }

        update(newest)
    }

    func liveRequests(at date: Date) -> [DeviceTransferRequest] {
        let nowInSeconds = UInt64(date.timeIntervalSince1970)
        let nowInMilliseconds = UInt64(date.timeIntervalSince1970.milliseconds)
        let maxAgeInMilliseconds = UInt64(DeviceTransferConstants.statementLifetimeInSeconds.milliseconds)

        let live = received.values.filter { $0.expiresAt > nowInSeconds }
        let cancelled = Set(live.compactMap { statement -> String? in
            guard case let .cancel(requestId) = statement.message else { return nil }
            return requestId.lowercased()
        })

        return live.compactMap { statement in
            guard
                case let .request(request) = statement.message,
                !cancelled.contains(request.requestId.lowercased()),
                nowInMilliseconds <= request.createdAt + maxAgeInMilliseconds
            else {
                return nil
            }

            return request
        }
    }

    func update(_ request: DeviceTransferRequest?) {
        guard subject.value != request else { return }
        subject.send(request)
    }
}
