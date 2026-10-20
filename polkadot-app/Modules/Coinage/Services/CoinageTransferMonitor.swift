import AsyncAlgorithms
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
    private let transferStatusService: any CoinageTransferStatusServicing
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
        transferStatusService: any CoinageTransferStatusServicing,
        denominationContext: @escaping DenominationContextProvider,
        transferStateStore: any TransferStateStoring,
        storageFacade: StorageFacadeProtocol,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        timing: Timing = .live,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.claimCoinsService = claimCoinsService
        self.transferStatusService = transferStatusService
        self.denominationContext = denominationContext
        self.transferStateStore = transferStateStore
        self.timing = timing
        self.logger = logger

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

        let task = Task { [claimCoinsService, denominationContext, transferStateStore, taskRegistry, logger] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await denominationContext()

                // Anchored to this device's first attempt so two devices' clocks never decide the window.
                let retryUntil = try await transferStateStore
                    .beginIncoming(messageId: messageId)
                    .addingTimeInterval(CoinageConstants.claimRetryWindow)

                logger.debug("Starting processing incoming coinage message=\(messageId)")

                let states = claimCoinsService.claim(
                    coinKeys: memo.entries,
                    groupId: messageId,
                    retryUntil: retryUntil,
                    context: context
                )
                .map(\.incomingState)
                .removeDuplicates()

                for try await state in states {
                    try await transferStateStore.updateIncoming(messageId: messageId, state: state)
                }
            } catch {
                // Not a status: the message is retried on the next snapshot or launch.
                logger.error("Failed to claim coinage for \(messageId): \(error)")
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
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
        let windowStatus = windowClosed(at: closesAt)
        let task = Task { [
            transferStatusService, denominationContext, transferStateStore, taskRegistry, logger, windowStatus
        ] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await denominationContext()

                logger.debug("Processing transfer for message: \(messageId) entries=\(memo.entries.count)")

                // Deduplicated by hand: the context is not Sendable, so it cannot ride a `map`.
                var lastState: OutgoingTransferState?
                let statuses = combineLatest(
                    transferStatusService.subscribeStatuses(coinKeys: memo.entries),
                    windowStatus
                )
                for try await (coinStates, isWindowClosed) in statuses {
                    let state = coinStates.outgoingState(context: context, windowClosed: isWindowClosed)
                    if state != lastState {
                        lastState = state
                        logger.debug("Status=\(state) message=\(messageId)")
                        try await transferStateStore.updateOutgoing(messageId: messageId, state: state)
                    }
                    if coinStates.isSettled { break }
                }
            } catch {
                logger.error("Send status monitoring failed for \(messageId): \(error)")
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }

    func windowClosed(at closesAt: Date) -> AsyncStream<Bool> {
        let timing = timing
        return AsyncStream { continuation in
            let task = Task {
                let now = await timing.dateProvider.read()
                let remaining = closesAt.timeIntervalSince(now)
                if remaining > 0 {
                    continuation.yield(false)
                    do {
                        try await timing.clock.sleep(for: .seconds(remaining))
                    } catch {
                        return
                    }
                }
                continuation.yield(true)
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
