import Foundation
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

struct DeviceTransferRequestTiming {
    var maxRequestAge: TimeInterval = DeviceTransferConstants.statementLifetimeInSeconds
    var dateProvider: any DateProviding = NowDateProvider()
    var clock: any Clock<Duration> = ContinuousClock()
}

/// The active phone's side of discovery. It follows `request_topic` only while this installation is active and offers
/// the newest request that hasn't expired, isn't older than the max request age, wasn't cancelled and wasn't processed.
actor DeviceTransferRequestListener {
    fileprivate struct ReceivedRequest {
        let request: DeviceTransferRequest
        let expiresAt: UInt64
    }

    private let keyScheduleFactory: DeviceTransferKeyScheduleMaking
    private let processedStore: DeviceTransferProcessedStoring
    private let installationObserver: CurrentInstallationObserving
    private let timing: DeviceTransferRequestTiming
    private let logger: LoggerProtocol

    private let subject = AsyncCurrentValueSubject<DeviceTransferRequest?>(nil)
    private var runTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    /// Only messages that decrypt are kept, keyed by request id, so statements flooding the topic can't grow memory.
    private var requests: [String: ReceivedRequest] = [:]
    private var cancellations: [String: UInt64] = [:]

    init(
        keyScheduleFactory: DeviceTransferKeyScheduleMaking,
        processedStore: DeviceTransferProcessedStoring,
        installationObserver: CurrentInstallationObserving,
        timing: DeviceTransferRequestTiming = DeviceTransferRequestTiming(),
        logger: LoggerProtocol
    ) {
        self.keyScheduleFactory = keyScheduleFactory
        self.processedStore = processedStore
        self.installationObserver = installationObserver
        self.timing = timing
        self.logger = logger
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
            let activity = await installationObserver.statusStream
                .map { $0 == .active }
                .removeDuplicates()

            for try await isActive in activity {
                try Task.checkCancellation()
                await stopFollowing()

                if isActive {
                    startFollowing(connection: connection)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Device transfer installation status stream failed: \(error)")
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

        expiryTask?.cancel()
        expiryTask = nil
        requests = [:]
        cancellations = [:]
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
        for encoded in encodedStatements {
            guard let (message, expiresAt) = parse(encoded, cipher: cipher) else { continue }

            switch message {
            case let .request(request):
                requests[request.requestId.lowercased()] = ReceivedRequest(request: request, expiresAt: expiresAt)
            case let .cancel(requestId):
                cancellations[requestId.lowercased()] = expiresAt
            }
        }

        try await evaluate()
    }

    func parse(_ encoded: Data, cipher: DeviceTransferMessageCipher) -> (DeviceTransferMessage, UInt64)? {
        guard
            let statement = try? Statement.fromScaleEncoded(encoded),
            let expiry = statement.getExpiry(),
            let payload = statement.getScaleEncodedPayload(),
            let sealed = try? Data.fromScaleEncoded(payload),
            let message = try? cipher.open(sealed)
        else {
            return nil
        }

        return (message, expiry >> 32)
    }

    func evaluate() async throws {
        let now = await timing.dateProvider.read()
        let liveRequests = liveRequests(at: now)
        let processed = try await processedStore.processedRequestIds(among: liveRequests.map(\.request.requestId))

        try Task.checkCancellation()

        let newest = liveRequests
            .filter { !processed.contains($0.request.requestId.lowercased()) }
            .max { $0.request.createdAt < $1.request.createdAt }

        update(newest?.request)
        scheduleExpiry(of: newest, now: now)
    }

    /// Statements only arrive when something changes, so the offered request is re-checked when it would expire.
    func scheduleExpiry(of offered: ReceivedRequest?, now: Date) {
        expiryTask?.cancel()
        expiryTask = nil

        guard let offered else { return }

        let nowInMilliseconds = UInt64(now.timeIntervalSince1970.milliseconds)
        let delay = withdrawalTime(of: offered).subtractingReportingOverflow(nowInMilliseconds)

        expiryTask = Task { [weak self, clock = timing.clock, logger] in
            do {
                try await clock.sleep(for: .milliseconds(delay.overflow ? 0 : delay.partialValue))
                try await self?.evaluate()
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Device transfer request expiry check failed: \(error)")
            }
        }
    }

    func liveRequests(at date: Date) -> [ReceivedRequest] {
        let nowInSeconds = UInt64(date.timeIntervalSince1970)
        let nowInMilliseconds = UInt64(date.timeIntervalSince1970.milliseconds)

        return requests.compactMap { requestId, received in
            let isCancelled = cancellations[requestId].map { $0 > nowInSeconds } ?? false

            guard !isCancelled, nowInMilliseconds < withdrawalTime(of: received) else {
                return nil
            }

            return received
        }
    }

    /// When the request stops being offered: its statement expires or it reaches the max age, whichever is first.
    func withdrawalTime(of received: ReceivedRequest) -> UInt64 {
        let tooOldAt = received.request.createdAt + UInt64(timing.maxRequestAge.milliseconds)
        let statementExpiredAt = UInt64(TimeInterval(received.expiresAt).milliseconds)
        return min(tooOldAt, statementExpiredAt)
    }

    func update(_ request: DeviceTransferRequest?) {
        guard subject.value != request else { return }
        subject.send(request)
    }
}
