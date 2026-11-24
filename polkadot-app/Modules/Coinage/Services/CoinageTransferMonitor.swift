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

    private let incoming: IncomingDependencies
    private let outgoing: OutgoingDependencies
    private let messageProviderFactory: ChatMessageDataProviderMaking
    private let logger: LoggerProtocol

    /// Top-level tasks that listen to the CoreData message streams.
    private var incomingTransfersSubscription: Task<Void, Never>?
    private var outgoingTransfersSubscription: Task<Void, Never>?

    /// Per-message tasks keyed by messageId. Each resolves independently, avoiding head-of-line
    /// blocking across messages.
    private let taskRegistry = ActiveTaskRegistry()

    init(
        claimCoinsService: any ClaimCoinsServicing,
        transferStatusService: any CoinageTransferStatusServicing,
        remoteTransferStatusService: any RemoteDeviceTransferStatusServicing,
        denominationContext: @escaping DenominationContextProvider,
        transferStateStore: any TransferStateStoring,
        storageFacade: StorageFacadeProtocol,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        timeSource: TimeSource = .live,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.logger = logger
        incoming = IncomingDependencies(
            claimCoinsService: claimCoinsService,
            denominationContext: denominationContext,
            transferStateStore: transferStateStore,
            logger: logger,
            timeSource: timeSource
        )
        outgoing = OutgoingDependencies(
            transferStatusService: transferStatusService,
            remoteTransferStatusService: remoteTransferStatusService,
            denominationContext: denominationContext,
            transferStateStore: transferStateStore,
            logger: logger,
            timeSource: timeSource
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
        let closesAt = Date.fromChatTimestamp(message.timestamp).addingTimeInterval(CoinageConstants.claimWindow)

        let task = Task { [incoming, taskRegistry] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await incoming.denominationContext()

                // Anchored to this device's first attempt so two devices' clocks never decide the window.
                let claimAnchor = try await incoming.transferStateStore.beginIncoming(messageId: messageId)
                let retryUntil = CoinageConstants.claimRetryWindow.map(claimAnchor.addingTimeInterval) ?? .distantFuture

                incoming.logger.debug("Starting processing incoming coinage message=\(messageId)")

                let detections = incoming.claimCoinsService.claim(
                    coinKeys: memo.entries,
                    groupId: messageId,
                    retryUntil: retryUntil,
                    context: context
                )
                let feed = IncomingFeed(
                    messageId: messageId,
                    detections: detections,
                    windowEvents: incoming.timeSource.fires(at: closesAt),
                    store: incoming.transferStateStore
                )
                try await CoinageTransferMonitor.followIncoming(
                    feed,
                    storedState: storedState,
                    isWindowClosed: incoming.timeSource.dateProvider.read() >= closesAt
                )
            } catch {
                // Not a status: the message is retried on the next snapshot or launch.
                incoming.logger.error("Failed to claim coinage for \(messageId): \(error)")
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }
}

private extension CoinageTransferMonitor {
    /// The claim's detections and the window's close, for one incoming message.
    struct IncomingFeed {
        let messageId: Chat.MessageId
        let detections: AnyAsyncSequence<CoinageTransferDetection>
        /// Merged with the detections so the state is recomputed at close even when the claim reports nothing then.
        let windowEvents: AsyncStream<Void>
        let store: any TransferStateStoring
    }

    static func followIncoming(
        _ feed: IncomingFeed,
        storedState: IncomingTransferState?,
        isWindowClosed: Bool
    ) async throws {
        var windowClosed = isWindowClosed
        var lastDetection: CoinageTransferDetection?
        var lastState = storedState
        let events = merge(
            feed.detections.map { IncomingMonitorEvent.detection($0) },
            feed.windowEvents.map { _ in IncomingMonitorEvent.windowClosed }
        )
        for try await event in events {
            switch event {
            case let .detection(detection): lastDetection = detection
            case .windowClosed: windowClosed = true
            }
            guard let state = lastDetection?.incomingState(windowClosed: windowClosed) else { continue }
            if state != lastState {
                lastState = state
                try await feed.store.updateIncoming(messageId: feed.messageId, state: state)
            }
            if state.isTerminal { break }
        }
    }
}

/// One input to the incoming loop: a claim detection or the one-time close of the claim window.
private enum IncomingMonitorEvent: Sendable {
    case detection(CoinageTransferDetection)
    case windowClosed
}

// MARK: - Outgoing (payment status)

private extension CoinageTransferMonitor {
    func subscribeOutgoingMessages() {
        logger.debug("Going to subscribe to outgoing messages")

        outgoingTransfersSubscription = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = messageProviderFactory.subscribeMessages(with: .outgoingCoinageSendMessages())
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
        let creationSource = message.creationSource
        let closesAt = Date.fromChatTimestamp(message.timestamp).addingTimeInterval(CoinageConstants.claimWindow)
        let task = Task { [outgoing, taskRegistry, closesAt] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await outgoing.denominationContext()

                outgoing.logger.debug("Processing transfer for message: \(messageId) entries=\(memo.entries.count)")

                switch creationSource {
                case .localDevice:
                    let isWindowClosed = await outgoing.timeSource.dateProvider.read() >= closesAt
                    try await CoinageTransferMonitor.followOutgoing(
                        outgoing.feed(messageId: messageId, memo: memo, closesAt: closesAt),
                        context: context,
                        isWindowClosed: isWindowClosed
                    )
                case .deviceSync:
                    try await CoinageTransferMonitor.followRemoteOutgoing(
                        outgoing.remoteFeed(messageId: messageId, memo: memo),
                        context: context
                    )
                }
            } catch {
                outgoing.logger.error("Send status monitoring failed for \(messageId): \(error)")
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
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
    /// The coin statuses and the window's close, for one outgoing message.
    struct OutgoingFeed {
        let messageId: Chat.MessageId
        let statuses: AnyAsyncSequence<[PublicKey: CoinageTransferState]>
        /// Merged with the statuses so the state is recomputed at close even when no coin status changes then.
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
        var latestCoinStates: [PublicKey: CoinageTransferState]?
        // Deduplicated by hand: the context is not Sendable, so it cannot ride a `map`.
        var lastState: OutgoingTransferState?
        let events = merge(
            feed.statuses.map { OutgoingMonitorEvent.statuses($0) },
            feed.windowEvents.map { _ in OutgoingMonitorEvent.windowClosed }
        )
        for try await event in events {
            switch event {
            case let .statuses(coinStates): latestCoinStates = coinStates
            case .windowClosed: windowClosed = true
            }
            guard let coinStates = latestCoinStates else { continue }
            let state = coinStates.outgoingState(context: context, windowClosed: windowClosed)
            if state != lastState {
                lastState = state
                feed.logger.debug("Status=\(state) message=\(feed.messageId)")
                try await feed.store.updateOutgoing(messageId: feed.messageId, state: state)
            }
            if coinStates.isSettled { break }
        }
    }

    /// A transfer sent from another device has no mint status and no claim window here, so only the
    /// finalized chain is read.
    struct RemoteOutgoingFeed {
        let messageId: Chat.MessageId
        let statuses: AnyAsyncSequence<[PublicKey: RemoteDeviceTransferCoinState]>
        let store: any TransferStateStoring
        let logger: LoggerProtocol
    }

    static func followRemoteOutgoing(_ feed: RemoteOutgoingFeed, context: DenominationBreakdownContext) async throws {
        var lastState: OutgoingTransferState?
        for try await coinStates in feed.statuses {
            let state = coinStates.outgoingState(context: context)
            if state != lastState {
                lastState = state
                feed.logger.debug("Status=\(state) message=\(feed.messageId)")
                try await feed.store.updateOutgoing(messageId: feed.messageId, state: state)
            }
            if coinStates.isSettled { break }
        }
    }
}

private struct IncomingDependencies {
    let claimCoinsService: any ClaimCoinsServicing
    let denominationContext: CoinageTransferMonitor.DenominationContextProvider
    let transferStateStore: any TransferStateStoring
    let logger: LoggerProtocol
    let timeSource: TimeSource
}

private struct OutgoingDependencies {
    let transferStatusService: any CoinageTransferStatusServicing
    let remoteTransferStatusService: any RemoteDeviceTransferStatusServicing
    let denominationContext: CoinageTransferMonitor.DenominationContextProvider
    let transferStateStore: any TransferStateStoring
    let logger: LoggerProtocol
    let timeSource: TimeSource

    func feed(messageId: Chat.MessageId, memo: TransferMemo, closesAt: Date) -> CoinageTransferMonitor.OutgoingFeed {
        CoinageTransferMonitor.OutgoingFeed(
            messageId: messageId,
            statuses: transferStatusService.subscribeStatuses(
                coinKeys: memo.entries,
                reclaimGroupId: ChatTransferGroups.reclaim(messageId)
            ),
            windowEvents: timeSource.fires(at: closesAt),
            store: transferStateStore,
            logger: logger
        )
    }

    func remoteFeed(messageId: Chat.MessageId, memo: TransferMemo) -> CoinageTransferMonitor.RemoteOutgoingFeed {
        CoinageTransferMonitor.RemoteOutgoingFeed(
            messageId: messageId,
            statuses: remoteTransferStatusService.subscribeStatuses(coinKeys: memo.entries),
            store: transferStateStore,
            logger: logger
        )
    }
}

/// One input to the outgoing loop: coin statuses or the one-time close of the claim window.
private enum OutgoingMonitorEvent: Sendable {
    case statuses([PublicKey: CoinageTransferState])
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
