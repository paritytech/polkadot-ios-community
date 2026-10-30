import AsyncAlgorithms
import AsyncExtensions
import BigInt
import Coinage
import CommonService
import Foundation
import FoundationExt
import Operation_iOS
import SubstrateSdk

/// Persists each chat transfer's lifecycle as its state row (``TransferStateStoring``). The status
/// comes only from the durability-derived streams: a thrown runtime error is never written, and a
/// message whose row is terminal never enters the subscriptions.
protocol CoinageTransferMonitoring: AsyncApplicationServicing {}

final class CoinageTransferMonitor {
    typealias DenominationContextProvider = @Sendable () async throws -> DenominationBreakdownContext

    /// The clock and date the claim window is checked against. Injected so tests drive the window from a test clock.
    struct Timing: Sendable {
        let clock: any Clock<Duration>
        let dateProvider: any DateProviding

        static let live = Timing(clock: ContinuousClock(), dateProvider: NowDateProvider())
    }

    private let claimCoinsService: any ClaimCoinsServicing
    private let outgoing: OutgoingDependencies
    private let denominationContext: DenominationContextProvider
    private let transferStateStore: any TransferStateStoring
    private let messageProviderFactory: ChatMessageDataProviderMaking
    private let timing: Timing
    private let logger: LoggerProtocol

    /// Top-level tasks that listen to the CoreData message streams.
    private var incomingTransfersSubscription: Task<Void, Never>?
    private var outgoingTransfersSubscription: Task<Void, Never>?

    /// Per-message tasks keyed by messageId. Each resolves independently, avoiding head-of-line
    /// blocking across messages.
    private let taskRegistry = ActiveTaskRegistry()

    init(
        claimCoinsService: any ClaimCoinsServicing,
        reclaimCoinsService: any ReclaimCoinsServicing,
        transferStatusService: any CoinageTransferStatusServicing,
        denominationContext: @escaping DenominationContextProvider,
        transferStateStore: any TransferStateStoring,
        storageFacade: StorageFacadeProtocol,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        timing: Timing = .live,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.claimCoinsService = claimCoinsService
        self.denominationContext = denominationContext
        self.transferStateStore = transferStateStore
        self.timing = timing
        self.logger = logger
        outgoing = OutgoingDependencies(
            transferStatusService: transferStatusService,
            reclaimCoinsService: reclaimCoinsService,
            denominationContext: denominationContext,
            transferStateStore: transferStateStore,
            logger: logger,
            timing: timing
        )

        let repositoryFactory = ChatMessageRepositoryFactory(storageFacade: storageFacade)
        messageProviderFactory = ChatMessageDataProviderFactory(
            repositoryFactory: repositoryFactory,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

extension CoinageTransferMonitor: CoinageTransferMonitoring {
    func setup() async {
        subscribeIncomingMessages()
        subscribeOutgoingMessages()
    }

    func throttle() async {
        incomingTransfersSubscription?.cancel()
        outgoingTransfersSubscription?.cancel()
        await taskRegistry.cancelAll()
    }
}

// MARK: - Incoming (claim)

private extension CoinageTransferMonitor {
    func subscribeIncomingMessages() {
        logger.debug("Going to subscribe to incoming messages")

        incomingTransfersSubscription = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = messageProviderFactory.subscribeMessages(with: .incomingCoinageSendMessages())
                for try await messages in stream {
                    try Task.checkCancellation()

                    logger.debug("Found \(messages.count) incoming coinage messages")

                    for message in messages {
                        await startIncoming(for: message)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Coinage claim subscription failed: \(error)")
            }
        }
    }

    func startIncoming(for message: Chat.LocalMessage) async {
        guard case let .coinageSend(content) = message.content else { return }
        let messageId = message.messageId
        guard await taskRegistry.contains(messageId) == false else { return }

        let memo = content.transferMemo
        let storedState = content.storedIncomingState

        let task = Task { [claimCoinsService, denominationContext, transferStateStore, taskRegistry, logger] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await denominationContext()

                // Anchored to this device's first attempt so two devices' clocks never decide the window.
                let retryUntil = try await transferStateStore
                    .beginIncoming(messageId: messageId)
                    .addingTimeInterval(CoinageConstants.claimRetryWindow)

                logger.debug("Starting processing incoming coinage message=\(messageId)")

                let detections = claimCoinsService.claim(
                    coinKeys: memo.entries,
                    groupId: messageId,
                    retryUntil: retryUntil,
                    context: context
                )
                let feed = IncomingFeed(
                    messageId: messageId,
                    detections: detections,
                    store: transferStateStore
                )
                try await CoinageTransferMonitor.followIncoming(feed, storedState: storedState)
            } catch {
                // Not a status: the message is retried on the next snapshot or launch.
                logger.error("Failed to claim coinage for \(messageId): \(error)")
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }
}

private extension CoinageTransferMonitor {
    /// The claim's detections for one incoming message.
    struct IncomingFeed {
        let messageId: Chat.MessageId
        let detections: AnyAsyncSequence<CoinageTransferDetection>
        let store: any TransferStateStoring
    }

    static func followIncoming(
        _ feed: IncomingFeed,
        storedState: IncomingTransferState?
    ) async throws {
        var lastState = storedState
        for try await detection in feed.detections {
            let state = detection.incomingState
            if state != lastState {
                lastState = state
                try await feed.store.updateIncoming(messageId: feed.messageId, state: state)
            }
            // Without this the loop would wait out the window after the claim's last word.
            if detection.isLastWord, state.isTerminal { break }
        }
    }
}

// MARK: - Outgoing (payment status)

private extension CoinageTransferMonitor {
    func subscribeOutgoingMessages() {
        logger.debug("Going to subscribe to outgoing messages")

        outgoingTransfersSubscription = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = messageProviderFactory.subscribeMessages(with: .outgoingLocalDeviceCoinageSendMessages())
                for try await messages in stream {
                    try Task.checkCancellation()
                    for message in messages {
                        await startOutgoing(for: message)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Coinage send subscription failed: \(error)")
            }
        }
    }

    func startOutgoing(for message: Chat.LocalMessage) async {
        guard case let .coinageSend(content) = message.content else { return }
        let messageId = message.messageId
        guard await taskRegistry.contains(messageId) == false else { return }

        let memo = content.transferMemo
        let closesAt = Date.fromChatTimestamp(message.timestamp).addingTimeInterval(CoinageConstants.claimWindow)
        let windowEvents = windowCloses(at: closesAt)
        let task = Task { [outgoing, taskRegistry, closesAt, windowEvents] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await outgoing.denominationContext()

                outgoing.logger.debug("Processing transfer for message: \(messageId) entries=\(memo.entries.count)")

                let isWindowClosed = await outgoing.timing.dateProvider.read() >= closesAt
                let feed = OutgoingFeed(
                    messageId: messageId,
                    statuses: outgoing.transferStatusService.subscribeStatuses(coinKeys: memo.entries),
                    failedReclaims: outgoing.reclaimCoinsService.subscribeFailedReclaims(
                        groupId: ChatTransferGroups.reclaim(messageId)
                    ),
                    windowEvents: windowEvents,
                    store: outgoing.transferStateStore,
                    logger: outgoing.logger
                )
                try await CoinageTransferMonitor.followOutgoing(
                    feed,
                    context: context,
                    isWindowClosed: isWindowClosed
                )
            } catch {
                outgoing.logger.error("Send status monitoring failed for \(messageId): \(error)")
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }

    /// Fires once when the claim window closes. An already-closed window fires at once without sleeping.
    func windowCloses(at closesAt: Date) -> AsyncStream<Void> {
        let timing = timing
        return AsyncStream { continuation in
            let task = Task {
                do {
                    var now = await timing.dateProvider.read()
                    while now < closesAt {
                        try await timing.clock.sleep(for: .seconds(closesAt.timeIntervalSince(now)))
                        now = await timing.dateProvider.read()
                    }
                } catch {
                    return
                }
                continuation.yield()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private extension Chat.LocalMessage.Content.Transfer {
    var transferMemo: TransferMemo {
        TransferMemo(entries: coinKeys, totalValue: totalValue)
    }

    var storedIncomingState: IncomingTransferState? {
        guard case let .incoming(stored)? = state else { return nil }
        return stored
    }
}

private extension CoinageTransferMonitor {
    /// The coin statuses, the failed reclaims and the window's close, for one outgoing message.
    struct OutgoingFeed {
        let messageId: Chat.MessageId
        let statuses: AnyAsyncSequence<[PublicKey: CoinageTransferState]>
        let failedReclaims: AnyAsyncSequence<Set<PublicKey>>
        let windowEvents: AsyncStream<Void>
        let store: any TransferStateStoring
        let logger: LoggerProtocol
    }

    static func followOutgoing(
        _ feed: OutgoingFeed,
        context: DenominationBreakdownContext,
        isWindowClosed: Bool
    ) async throws {
        var windowClosed = isWindowClosed
        var failedIterator = feed.failedReclaims.makeAsyncIterator()
        // Seeded with the current failed set, so no status is read before its failed reclaims are known.
        var latestFailedReclaims = try await failedIterator.next() ?? []
        var latestCoinStates: [PublicKey: CoinageTransferState]?
        // Deduplicated by hand: the context is not Sendable, so it cannot ride a `map`.
        var lastState: OutgoingTransferState?
        let events = merge(
            feed.statuses.map { OutgoingMonitorEvent.statuses($0) },
            laterFailedReclaims(failedIterator).map { OutgoingMonitorEvent.failedReclaims($0) },
            feed.windowEvents.map { _ in OutgoingMonitorEvent.windowClosed }
        )
        for try await event in events {
            switch event {
            case let .statuses(coinStates): latestCoinStates = coinStates
            case let .failedReclaims(failedKeys): latestFailedReclaims = failedKeys
            case .windowClosed: windowClosed = true
            }
            guard let coinStates = latestCoinStates else { continue }
            let state = coinStates.outgoingState(
                context: context,
                failedReclaims: latestFailedReclaims,
                windowClosed: windowClosed
            )
            if state != lastState {
                lastState = state
                feed.logger.debug("Status=\(state) message=\(feed.messageId)")
                try await feed.store.updateOutgoing(messageId: feed.messageId, state: state)
            }
            if coinStates.isSettled { break }
        }
    }

    /// The failed reclaims after the first value, pulled from the iterator that already produced that value.
    static func laterFailedReclaims(
        _ iterator: AnyAsyncSequence<Set<PublicKey>>.AsyncIterator
    ) -> AsyncThrowingStream<Set<PublicKey>, Error> {
        AsyncThrowingStream { continuation in
            var iterator = iterator
            let pump = Task {
                do {
                    while let failed = try await iterator.next() {
                        continuation.yield(failed)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
    }
}

private struct OutgoingDependencies {
    let transferStatusService: any CoinageTransferStatusServicing
    let reclaimCoinsService: any ReclaimCoinsServicing
    let denominationContext: CoinageTransferMonitor.DenominationContextProvider
    let transferStateStore: any TransferStateStoring
    let logger: LoggerProtocol
    let timing: CoinageTransferMonitor.Timing
}

/// One input to the outgoing loop: coin statuses, the failed reclaims, or the one-time close of the claim window.
private enum OutgoingMonitorEvent: Sendable {
    case statuses([PublicKey: CoinageTransferState])
    case failedReclaims(Set<PublicKey>)
    case windowClosed
}

// MARK: - Active Task Registry

private actor ActiveTaskRegistry {
    private var tasks: [String: Task<Void, Never>] = [:]

    func register(_ task: Task<Void, Never>, forMessageId id: String) {
        tasks[id] = task
    }

    func remove(forMessageId id: String) {
        tasks.removeValue(forKey: id)
    }

    func contains(_ id: String) -> Bool {
        tasks[id] != nil
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
