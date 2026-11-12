import AsyncAlgorithms
import AsyncExtensions
import BigInt
import Coinage
import CommonService
import Foundation
import Operation_iOS
import SubstrateSdk

/// Persists each chat transfer's lifecycle as its state row (``TransferStateStoring``). The status
/// comes only from the durability-derived streams: a thrown runtime error is never written, and a
/// message whose row is terminal never enters the subscriptions.
protocol CoinageTransferMonitoring: AsyncApplicationServicing {}

final class CoinageTransferMonitor {
    typealias DenominationContextProvider = @Sendable () async throws -> DenominationBreakdownContext

    private let claimCoinsService: any ClaimCoinsServicing
    private let transferStatusService: any CoinageTransferStatusServicing
    private let remoteTransferStatusService: any RemoteDeviceTransferStatusServicing
    private let denominationContext: DenominationContextProvider
    private let transferStateStore: any TransferStateStoring
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
        logger: LoggerProtocol = Logger.shared
    ) {
        self.claimCoinsService = claimCoinsService
        self.transferStatusService = transferStatusService
        self.remoteTransferStatusService = remoteTransferStatusService
        self.denominationContext = denominationContext
        self.transferStateStore = transferStateStore
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
                let claimAnchor = try await transferStateStore.beginIncoming(messageId: messageId)
                let retryUntil = CoinageConstants.claimRetryWindow.map(claimAnchor.addingTimeInterval) ?? .distantFuture

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

    /// A transfer from another device has no mint status here, so only the chain is read.
    func startOutgoing(for message: Chat.LocalMessage) async {
        guard case let .coinageSend(content) = message.content else { return }
        let messageId = message.messageId
        guard await taskRegistry.contains(messageId) == false else { return }

        let memo = content.transferMemo
        let states: AnyAsyncSequence<OutgoingTransferState> =
            switch message.creationSource {
            case .localDevice:
                outgoingStates(
                    of: transferStatusService.subscribeStatuses(coinKeys: memo.entries),
                    state: { $0.outgoingState(context: $1) },
                    isSettled: { $0.isSettled }
                )
            case .deviceSync:
                outgoingStates(
                    of: remoteTransferStatusService.subscribeStatuses(coinKeys: memo.entries),
                    state: { $0.outgoingState(context: $1) },
                    isSettled: { $0.isSettled }
                )
            }

        let task = Task { [transferStateStore, taskRegistry, logger] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                logger.debug("Processing transfer for message: \(messageId) entries=\(memo.entries.count)")

                for try await state in states {
                    logger.debug("Status=\(state) message=\(messageId)")
                    try await transferStateStore.updateOutgoing(messageId: messageId, state: state)
                }
            } catch {
                logger.error("Send status monitoring failed for \(messageId): \(error)")
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }

    /// Deduplicated by hand: the context is not Sendable, so it cannot ride a `map`.
    func outgoingStates<Snapshot: Sendable>(
        of snapshots: AnyAsyncSequence<Snapshot>,
        state: @escaping @Sendable (Snapshot, DenominationBreakdownContext) -> OutgoingTransferState,
        isSettled: @escaping @Sendable (Snapshot) -> Bool
    ) -> AnyAsyncSequence<OutgoingTransferState> {
        AsyncThrowingStream<OutgoingTransferState, Error> { [denominationContext] continuation in
            let task = Task {
                do {
                    let context = try await denominationContext()
                    var lastState: OutgoingTransferState?

                    for try await snapshot in snapshots {
                        let next = state(snapshot, context)
                        if next != lastState {
                            lastState = next
                            continuation.yield(next)
                        }
                        if isSettled(snapshot) { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        .eraseToAnyAsyncSequence()
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
