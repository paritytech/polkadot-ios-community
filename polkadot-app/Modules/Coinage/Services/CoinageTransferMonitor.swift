import BigInt
import Coinage
import CommonService
import Foundation
import Operation_iOS
import SubstrateSdk

/// Monitors coinage transfer lifecycle for both directions:
/// - Incoming: claims transferred coins on behalf of the recipient
/// - Outgoing: verifies destination coins appeared on-chain
/// - Startup: restores persisted statuses from ``ClaimPlanCoreDataStore``
protocol CoinageTransferMonitoring: AsyncApplicationServicing {}

final class CoinageTransferMonitor {
    private let coinageService: any CoinageServicing
    private let claimService: any TransferClaimServicing
    private let sendVerifier: any TransferSendVerifying
    private let planStore: any ClaimPlanStoring
    private let messageProviderFactory: ChatMessageDataProviderMaking
    private let claimStatusStore: ClaimStatusStore
    private let logger: LoggerProtocol

    /// Top-level tasks that listen to the CoreData message streams.
    private var incomingTransfersSubscription: Task<Void, Never>?
    private var outgoingTransfersSubscription: Task<Void, Never>?

    /// Per-message tasks keyed by messageId. Each task subscribes to on-chain state
    /// and resolves independently, avoiding head-of-line blocking across messages.
    private let taskRegistry = ActiveTaskRegistry()

    /// Maximum finalized blocks to wait for coins to appear on-chain before marking as failed.
    private static let sendVerifyBlockTimeout: UInt32 = 100

    init(
        coinageService: any CoinageServicing,
        planStore: any ClaimPlanStoring,
        storageFacade: StorageFacadeProtocol,
        claimStatusStore: ClaimStatusStore,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.coinageService = coinageService
        claimService = coinageService.ongoingTransferService
        sendVerifier = coinageService.ongoingTransferService
        self.planStore = planStore
        self.claimStatusStore = claimStatusStore
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
        restorePersistedStatuses()
        subscribeIncomingMessages()
        subscribeOutgoingMessages()
    }

    func throttle() async {
        incomingTransfersSubscription?.cancel()
        outgoingTransfersSubscription?.cancel()
        await taskRegistry.cancelAll()
    }
}

// MARK: - Status Restoration

private extension CoinageTransferMonitor {
    func restorePersistedStatuses() {
        Task { [planStore, claimStatusStore, logger] in
            let plans: [ClaimPlan]
            do {
                plans = try await planStore.loadAll()
            } catch {
                logger.error("Failed to load claim plans for status restoration: \(error)")
                return
            }

            for plan in plans {
                await claimStatusStore.updateStatus(plan.claimStatus, forMessageId: plan.messageId)
            }

            guard !plans.isEmpty else {
                return
            }
            logger.debug("Restored \(plans.count) persisted claim statuses")
        }
    }
}

// MARK: - Claimed Amount Computation

private extension CoinageTransferMonitor {
    func computeClaimedAmount(from plan: ClaimPlan) async throws -> Balance {
        let context = try await coinageService.denominationContext()

        guard !plan.entries.isEmpty else {
            return plan.totalValue
        }

        return plan.entries.reduce(BigUInt(0)) { sum, entry in
            sum + context.valueInPlanks(for: entry.destinationCoin.exponent)
        }
    }
}

// MARK: - Incoming (Claim)

private extension CoinageTransferMonitor {
    func subscribeIncomingMessages() {
        incomingTransfersSubscription = Task { [weak self, claimStatusStore] in
            guard let self else { return }

            do {
                let stream = messageProviderFactory.subscribeMessages(with: .incomingCoinageSendMessages())

                for try await messages in stream {
                    try Task.checkCancellation()

                    for message in messages {
                        guard
                            case let .coinageSend(sendContent) = message.content
                        else {
                            continue
                        }

                        let messageId = message.messageId
                        guard await taskRegistry.contains(messageId) == false else {
                            continue
                        }

                        if case .finished = await claimStatusStore.status(forMessageId: messageId) {
                            continue
                        }

                        let memo = sendContent.transferMemo

                        // swiftlint:disable closure_parameter_position
                        let task = Task { [
                            taskRegistry,
                            claimService,
                            sendVerifier,
                            planStore,
                            claimStatusStore,
                            logger
                        ] in
                            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
                            do {
                                await claimStatusStore.updateStatus(.detecting, forMessageId: messageId)

                                // Existing plan means some coins may already
                                // be claimed (spent), so awaitSendOnChain would timeout waiting
                                // for keys that will never reappear. Skip the await in that case —
                                // claim() handles partially-spent memos gracefully.
                                let existingPlan = await (try? planStore.plan(memo: memo))

                                if let existingPlan {
                                    guard existingPlan.status != .finished else {
                                        return
                                    }
                                } else {
                                    try await sendVerifier.awaitSendOnChain(
                                        memo: memo,
                                        blockTimeout: CoinageTransferMonitor.sendVerifyBlockTimeout
                                    )
                                }

                                await claimStatusStore.updateStatus(.claiming, forMessageId: messageId)

                                try await claimService.claim(memo: memo, messageId: messageId)

                                // Compute claimed amount from plan entries + denomination context.
                                // denominationContext() suspends until setup completes,
                                // avoiding a race where context is nil mid-setup.
                                let plan = await (try? planStore.plan(memo: memo))
                                let claimedAmount: Balance =
                                    if let plan {
                                        try await self.computeClaimedAmount(from: plan)
                                    } else {
                                        memo.totalValue
                                    }

                                try? await planStore.updateStatus(
                                    .finished,
                                    claimedAmount: claimedAmount,
                                    forMemo: memo
                                )
                                await claimStatusStore.updateStatus(
                                    .finished(claimedAmount: claimedAmount),
                                    forMessageId: messageId
                                )
                                logger.debug("Successfully claimed coinage send content for \(messageId)")
                            } catch TransferRecipientError.alreadyClaiming {
                                logger.debug("Memo already being claimed, skipping.")
                            } catch {
                                logger.error("Failed to claim coinage for \(messageId): \(error)")
                                await claimStatusStore.updateStatus(.error, forMessageId: messageId)
                            }
                        }
                        // swiftlint:enable closure_parameter_position

                        await taskRegistry.register(task, forMessageId: messageId)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Coinage claim task failed: \(error)")
            }
        }
    }
}

// MARK: - Outgoing (Send Verification)

private extension CoinageTransferMonitor {
    func subscribeOutgoingMessages() {
        outgoingTransfersSubscription = Task { [weak self, claimStatusStore] in
            guard let self else { return }

            do {
                let stream = messageProviderFactory.subscribeMessages(
                    with: .outgoingLocalDeviceCoinageSendMessages()
                )

                for try await messages in stream {
                    try Task.checkCancellation()

                    for message in messages {
                        guard
                            case let .coinageSend(sendContent) = message.content
                        else {
                            continue
                        }

                        let messageId = message.messageId
                        guard await taskRegistry.contains(messageId) == false else {
                            continue
                        }

                        if case .finished = await claimStatusStore.status(forMessageId: messageId) {
                            continue
                        }

                        let memo = sendContent.transferMemo

                        let task = Task { [taskRegistry, planStore, sendVerifier, claimStatusStore, logger] in
                            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }

                            do {
                                let existingPlan = await (try? planStore.plan(memo: memo))

                                if existingPlan?.status == .detected {
                                    // Coins were confirmed on-chain in a prior run; skip awaitSendOnChain.
                                    await claimStatusStore.updateStatus(.sent, forMessageId: messageId)
                                } else {
                                    // Persist plan if not yet saved; always await send — plan is saved
                                    // before coins appear, so existence alone doesn't imply on-chain presence.
                                    if existingPlan == nil {
                                        let plan = ClaimPlan(
                                            memoKey: memo.identifier(),
                                            messageId: messageId,
                                            entries: [],
                                            status: .processing,
                                            totalValue: memo.totalValue
                                        )
                                        try? await planStore.save(plan: plan)
                                    }

                                    await claimStatusStore.updateStatus(.detecting, forMessageId: messageId)

                                    try await sendVerifier.awaitSendOnChain(
                                        memo: memo,
                                        blockTimeout: CoinageTransferMonitor.sendVerifyBlockTimeout
                                    )

                                    try? await planStore.updateStatus(.detected, claimedAmount: nil, forMemo: memo)
                                    await claimStatusStore.updateStatus(.sent, forMessageId: messageId)
                                }

                                try await sendVerifier.awaitClaimOnChain(
                                    memo: memo,
                                    blockTimeout: CoinageTransferMonitor.sendVerifyBlockTimeout
                                )

                                try? await planStore.updateStatus(
                                    .finished,
                                    claimedAmount: memo.totalValue,
                                    forMemo: memo
                                )
                                await claimStatusStore.updateStatus(
                                    .finished(claimedAmount: memo.totalValue),
                                    forMessageId: messageId
                                )
                                logger.debug("Send verified and claimed for message \(messageId)")
                            } catch {
                                try? await planStore.updateStatus(.error, claimedAmount: nil, forMemo: memo)
                                await claimStatusStore.updateStatus(.error, forMessageId: messageId)
                                logger.error("Send/claim verification failed for \(messageId): \(error)")
                            }
                        }
                        await taskRegistry.register(task, forMessageId: messageId)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Send verification task failed: \(error)")
            }
        }
    }
}

private extension Chat.LocalMessage.Content.Transfer {
    var transferMemo: TransferMemo {
        TransferMemo(entries: coinKeys, totalValue: totalValue)
    }
}

private extension ClaimPlan {
    var claimStatus: ClaimStatus {
        switch status {
        case .finished:
            let amount = claimedAmount ?? totalValue
            return .finished(claimedAmount: amount)
        case .error:
            return .error
        case .processing:
            return .detecting
        case .detected:
            return .sent
        }
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
