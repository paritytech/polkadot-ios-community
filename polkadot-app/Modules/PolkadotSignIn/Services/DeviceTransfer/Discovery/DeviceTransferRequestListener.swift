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

/// The active phone's side of discovery. It follows `request_topic` only while this installation is active and offers
/// the newest request that hasn't expired, isn't older than 15 minutes, wasn't cancelled and wasn't processed.
actor DeviceTransferRequestListener {
    fileprivate struct ReceivedRequest {
        let request: DeviceTransferRequest
        let expiresAt: UInt64
    }

    private let keyScheduleFactory: DeviceTransferKeyScheduleMaking
    private let processedStore: DeviceTransferProcessedStoring
    private let installationObserver: CurrentInstallationObserving
    private let dateProvider: any DateProviding
    private let logger: LoggerProtocol

    private let subject = AsyncCurrentValueSubject<DeviceTransferRequest?>(nil)
    private var runTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    /// Only messages that decrypt are kept, keyed by request id, so statements flooding the topic can't grow memory.
    private var requests: [String: ReceivedRequest] = [:]
    private var cancellations: [String: UInt64] = [:]

    init(
        keyScheduleFactory: DeviceTransferKeyScheduleMaking,
        processedStore: DeviceTransferProcessedStoring,
        installationObserver: CurrentInstallationObserving,
        dateProvider: any DateProviding = NowDateProvider(),
        logger: LoggerProtocol
    ) {
        self.keyScheduleFactory = keyScheduleFactory
        self.processedStore = processedStore
        self.installationObserver = installationObserver
        self.dateProvider = dateProvider
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

        return requests.compactMap { requestId, received in
            let isCancelled = cancellations[requestId].map { $0 > nowInSeconds } ?? false

            guard
                received.expiresAt > nowInSeconds,
                !isCancelled,
                nowInMilliseconds <= received.request.createdAt + maxAgeInMilliseconds
            else {
                return nil
            }

            return received.request
        }
    }

    func update(_ request: DeviceTransferRequest?) {
        guard subject.value != request else { return }
        subject.send(request)
    }
}
