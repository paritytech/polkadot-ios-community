import AsyncExtensions
import BigInt
import Foundation
import NovaCrypto
import SDKLogger
import SubstrateSdk
import SubstrateOperation

/// Claims transferred coins on behalf of the recipient.
public protocol TransferClaimServicing: Actor {
    func claim(memo: TransferMemo, messageId: String) async throws

    /// Detects on-chain coins for the given sr25519 secret keys; when
    /// `transferCoins` is true, also claims them into the user's coin set.
    /// Returns the total detected value in planks (0 if none found).
    func transferCoinsFromSecretKeys(
        secretKeys: [Data],
        transferCoins: Bool,
        context: DenominationBreakdownContext
    ) async throws -> BigUInt

    /// Recovers locally-spent coins that may still be on-chain:
    /// - Coins whose on-chain age has reached `coinMaxAge` are flipped back to
    ///   `.available` locally — the chain would reject a transfer for them, so we
    ///   leave them in place and rely on the recycling service to sweep them next.
    /// - Younger coins are revoked by transferring them to fresh destinations.
    /// Returns the total planks recovered across both paths.
    func recoverSpentCoins(
        spentCoins: [Coin],
        context: DenominationBreakdownContext
    ) async throws -> BigUInt
}

/// Outcome of a send confirmation that tolerates a recipient claim.
public enum SendConfirmation: Sendable {
    /// At least one coin is still on-chain — send confirmed, awaiting claim.
    case onChain
    /// All coins are confirmed sent then spent — the recipient already claimed.
    case alreadyClaimed
}

/// Waits until outgoing transfer coins have appeared on-chain, or throws on timeout.
public protocol TransferSendVerifying: Actor {
    func awaitSendOnChain(memo: TransferMemo, blockTimeout: UInt32) async throws
    func awaitClaimOnChain(memo: TransferMemo, blockTimeout: UInt32) async throws

    /// Confirms the transfer reached the chain even if the recipient already claimed some or all
    /// coins. `anchorBlock` (e.g. submit-time finalized block + send window) enables a historical
    /// probe for coins spent before this watch began. Throws `CoinOnChainQueryError.timeout` only
    /// when a coin is neither present now, nor seen during the watch, nor present at the anchor —
    /// i.e. a genuine lost send.
    func awaitSendOrClaimed(
        memo: TransferMemo,
        anchorBlock: BlockNumber?,
        blockTimeout: UInt32
    ) async throws -> SendConfirmation
}

public extension TransferSendVerifying {
    /// Default: fall back to strict presence detection (no claim tolerance).
    func awaitSendOrClaimed(
        memo: TransferMemo,
        anchorBlock _: BlockNumber?,
        blockTimeout: UInt32
    ) async throws -> SendConfirmation {
        try await awaitSendOnChain(memo: memo, blockTimeout: blockTimeout)
        return .onChain
    }
}

/// Combined protocol for services that handle both claiming and send verification.
public typealias OngoingTransferServicing = TransferClaimServicing & TransferSendVerifying

public enum TransferRecipientError: Error {
    case coinNotFound
    case alreadyClaiming
}

public struct ClaimReport {
    public let claimed: [Coin]
    public let alreadyTransferred: [Coin]
    public let externallySpent: Int
    public let failures: [(entryIndex: Int, error: Error)]

    public var totalReceived: Int {
        claimed.count + alreadyTransferred.count
    }
}

actor TransferRecipientService {
    typealias OnChainCoin = CoinSyncResult.OnChainCoin
    private typealias HeadsSharedStream = AsyncShareSequence<AnyAsyncSequence<Block.Header>>

    private let coinAllocator: any CoinAllocating
    private let coinKeyFactory: any CoinKeyDeriving
    private let coinService: any CoinServiceProtocol
    private let coinOnChainQuery: any CoinOnChainQuerying
    private let transferSubmitter: any CoinTransferSubmitting
    private let snKeyFactory: any SNKeyFactoryProtocol
    private let planStore: any ClaimPlanStoring
    private let blockNumberProvider: any BlockInfoProviding
    private let logger: SDKLoggerProtocol?

    /// In-memory deduplication of in-flight memo claims.
    private var claimingMemos: Set<Data> = []

    /// Shared finalized-head multicast.
    /// Started on first `awaitSendOnChain` caller, released on last.
    private var headsSharedStream: HeadsSharedStream?
    private var headsWaiterCount = 0

    init(
        coinAllocator: any CoinAllocating,
        coinKeyFactory: any CoinKeyDeriving,
        coinService: any CoinServiceProtocol,
        coinOnChainQuery: any CoinOnChainQuerying,
        transferSubmitter: any CoinTransferSubmitting,
        snKeyFactory: any SNKeyFactoryProtocol,
        planStore: any ClaimPlanStoring,
        blockNumberProvider: any BlockInfoProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.coinAllocator = coinAllocator
        self.coinKeyFactory = coinKeyFactory
        self.coinService = coinService
        self.coinOnChainQuery = coinOnChainQuery
        self.transferSubmitter = transferSubmitter
        self.snKeyFactory = snKeyFactory
        self.planStore = planStore
        self.blockNumberProvider = blockNumberProvider
        self.logger = logger
    }
}

// MARK: - Cancellable async sequence wrapper

private extension AsyncSequence where Element: Sendable, AsyncIterator: Sendable {
    /// Bridges a non-cancellation-aware async sequence (e.g. an AsyncExtensions multicast
    /// subject) into an AsyncStream that finishes promptly when the consuming task is
    /// cancelled, instead of staying suspended until the next upstream element.
    func cancellable() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await element in self {
                        continuation.yield(element)
                    }
                } catch {}
                continuation.finish()
            }
            // `onTermination` fires immediately when the consumer's task is cancelled (AsyncStream
            // iterators are cancellation-aware), so the counter loop unblocks at once. The pump task,
            // however, is suspended on the upstream multicast subject, which is NOT cancellation-aware:
            // it only observes this `cancel()` on the next upstream element (or upstream finish).
            // So the pump — and its consumer slot on the shared head subscription — may linger up to
            // one block before tearing down. Bounded and self-healing; do not "fix" by awaiting it.
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension TransferRecipientService: OngoingTransferServicing {
    func claim(memo: TransferMemo, messageId: String) async throws {
        logger?.debug("Claiming memo with \(memo.entries.count) entries")

        let memoKey = memo.identifier()

        guard claimingMemos.insert(memoKey).inserted else {
            logger?.error("Already claiming this memo")
            throw TransferRecipientError.alreadyClaiming
        }

        defer { claimingMemos.remove(memoKey) }

        // Check for an existing plan (recovery after crash)
        let existingPlan = try? await planStore.plan(memo: memo)

        let report: ClaimReport
        if let existingPlan {
            logger?.debug("Found existing plan for memo, reusing allocated coins")
            report = await claimFromPlan(existingPlan, memo: memo)
        } else {
            report = await claimAll(memo: memo, messageId: messageId)
        }

        let coinsToSave = report.claimed + report.alreadyTransferred
        if !coinsToSave.isEmpty {
            try await coinService.save(coins: coinsToSave)
            logger?.debug("Saved \(coinsToSave.count) claimed coins")
        }

        if !report.failures.isEmpty {
            logger?.error("Claim had \(report.failures.count) failures")
        }

        let hasSuccess = !report.claimed.isEmpty || !report.alreadyTransferred.isEmpty

        // Update plan status; keep for partial failure retry
        if report.failures.isEmpty {
            try? await planStore.updateStatus(.finished, forMemo: memo)
        } else {
            try? await planStore.updateStatus(.error, forMemo: memo)
        }

        guard hasSuccess else {
            if let errorTuple = report.failures.first {
                throw errorTuple.error
            }
            return
        }

        logger?.debug(
            "Claim completed - claimed: \(report.claimed.count)/\(memo.entries.count), already transferred: \(report.alreadyTransferred.count)"
        )
    }

    func transferCoinsFromSecretKeys(
        secretKeys: [Data],
        transferCoins: Bool,
        context: DenominationBreakdownContext
    ) async throws -> BigUInt {
        guard !secretKeys.isEmpty else { return 0 }

        let publicKeys: [PublicKey] = try secretKeys.map {
            try snKeyFactory.createPublicKey(fromSecret: $0).rawData()
        }
        let onChainCoins = try await coinOnChainQuery.fetchCoins(for: publicKeys)

        var total: BigUInt = 0
        for coin in onChainCoins {
            guard let coin else { continue }
            total += context.valueInPlanks(for: Int16(coin.value))
        }

        guard transferCoins, total > 0 else { return total }

        let memo = TransferMemo(entries: secretKeys, totalValue: total)
        // Deterministic per (keys, value) — retries dedup against any in-flight claim.
        let messageId = "w3s-coins-\(memo.identifier().toHex())"
        try await claim(memo: memo, messageId: messageId)
        return total
    }

    func recoverSpentCoins(
        spentCoins: [Coin],
        context: DenominationBreakdownContext
    ) async throws -> BigUInt {
        guard !spentCoins.isEmpty else { return .zero }

        let senderKeys: [SenderKey] = try spentCoins.enumerated().map { index, coin in
            let privateKey = try coinKeyFactory.derivePrivateKey(for: coin)
            let publicKey = try snKeyFactory.createPublicKey(fromSecret: privateKey).rawData()
            return (index, privateKey, publicKey)
        }

        let sourceCoins = try await coinOnChainQuery.fetchCoins(for: senderKeys.map(\.publicKey))

        let restoredPlanks = try await restoreMaxAgeCoins(
            spentCoins: spentCoins,
            sourceCoins: sourceCoins,
            context: context
        )

        let (transferableKeys, transferableSources) = filterTransferable(
            senderKeys: senderKeys,
            sourceCoins: sourceCoins
        )

        var failures: [EntryFailure] = []
        let (prepared, _) = await allocateDestinations(
            senderKeys: transferableKeys,
            sourceCoins: transferableSources,
            failures: &failures
        )

        guard !prepared.isEmpty else { return restoredPlanks }

        let (claimed, submitFailures) = await submitTransfers(prepared)
        failures.append(contentsOf: submitFailures)

        if !claimed.isEmpty {
            try await coinService.save(coins: claimed)
            logger?.debug("Saved \(claimed.count) revoked coins")
        }

        if !failures.isEmpty {
            logger?.error("Revoke had \(failures.count) failures")
        }

        let transferredPlanks = claimed.reduce(.zero) { $0 + context.valueInPlanks(for: $1.exponent) }
        return restoredPlanks + transferredPlanks
    }

    /// Derives sender public keys, then races a finalized-block counter against the coin subscription.
    ///
    /// All concurrent callers share one `subscribeFinalizedHeads()` WebSocket subscription
    /// via `headsShare`. Throws `CoinOnChainQueryError.timeout` once `blockTimeout` finalized
    /// heads have been observed without all coins appearing on-chain.
    func awaitSendOnChain(memo: TransferMemo, blockTimeout: UInt32) async throws {
        guard !memo.entries.isEmpty else { return }

        let publicKeys: [PublicKey] = try memo.entries.map {
            try snKeyFactory.createPublicKey(fromSecret: $0).rawData()
        }

        let stream = acquireHeadStream()
        defer { releaseHeadStream() }

        logger?.debug("\(memo.identifier().toHexString()) start, timeout \(blockTimeout) blocks")

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [logger] in
                var count: UInt32 = 0
                for try await header in stream.cancellable() {
                    count += 1
                    if count == 1 {
                        logger?.debug(
                            "\(memo.identifier().toHexString()) started from block \(header.number.hexBlockNumber)"
                        )
                    }
                    if count >= blockTimeout {
                        throw CoinOnChainQueryError.timeout
                    }
                }
                throw CoinOnChainQueryError.subscriptionTerminated
            }

            group.addTask { [self] in
                try await coinOnChainQuery.awaitAllCoinsOnChain(for: publicKeys)
            }

            try await group.next()
            group.cancelAll()
        }
    }

    /// Waits until transferred coins have been claimed and are no longer on-chain.
    ///
    /// Derives destination public keys from memo entries (opposite of awaitSendOnChain),
    /// then races a finalized-block counter against the coin subscription. Completes when
    /// all coin keys are absent/spent on-chain (recipient has claimed them), or throws
    /// `CoinOnChainQueryError.timeout` after `blockTimeout` blocks.
    func awaitClaimOnChain(memo: TransferMemo, blockTimeout: UInt32) async throws {
        guard !memo.entries.isEmpty else { return }

        let publicKeys: [PublicKey] = try memo.entries.map {
            try snKeyFactory.createPublicKey(fromSecret: $0).rawData()
        }

        let stream = acquireHeadStream()
        defer { releaseHeadStream() }

        logger?.debug("\(memo.identifier().toHexString()) start, timeout \(blockTimeout) blocks")

        try await withThrowingTaskGroup(of: Void.self) { [logger] group in
            group.addTask {
                var count: UInt32 = 0
                for try await header in stream.cancellable() {
                    count += 1
                    if count == 1 {
                        logger?.debug(
                            "\(memo.identifier().toHexString()) started from block \(header.number.hexBlockNumber)"
                        )
                    }
                    if count >= blockTimeout {
                        throw CoinOnChainQueryError.timeout
                    }
                }
                throw CoinOnChainQueryError.subscriptionTerminated
            }

            group.addTask { [self] in
                try await coinOnChainQuery.awaitAllCoinsOffChain(for: publicKeys)
            }

            try await group.next()
            group.cancelAll()
        }
    }

    func awaitSendOrClaimed(
        memo: TransferMemo,
        anchorBlock: BlockNumber?,
        blockTimeout: UInt32
    ) async throws -> SendConfirmation {
        guard !memo.entries.isEmpty else { return .onChain }

        let publicKeys: [PublicKey] = try memo.entries.map {
            try snKeyFactory.createPublicKey(fromSecret: $0).rawData()
        }

        var confirmed = Set<Int>()
        var anyPresentNow = false

        // 1. Current on-chain state.
        let current = try await coinOnChainQuery.fetchCoins(for: publicKeys, atBlockHash: nil)
        for (index, coin) in current.enumerated() where coin != nil {
            confirmed.insert(index)
            anyPresentNow = true
        }

        // 2. Historical probe: a coin spent before this watch is absent now but was present at the
        //    anchor block. Best-effort — a future/unavailable anchor simply skips this step.
        if confirmed.count < publicKeys.count, let anchorBlock {
            let absentIndices = (0 ..< publicKeys.count).filter { !confirmed.contains($0) }
            if let anchorHash = try? await blockNumberProvider.fetchBlockHash(anchorBlock) {
                let absentKeys = absentIndices.map { publicKeys[$0] }
                let historical = try await coinOnChainQuery.fetchCoins(
                    for: absentKeys,
                    atBlockHash: anchorHash
                )
                for (offset, coin) in historical.enumerated() where coin != nil {
                    confirmed.insert(absentIndices[offset])
                }
            }
        }

        if confirmed.count == publicKeys.count {
            return anyPresentNow ? .onChain : .alreadyClaimed
        }

        // 3. Live subscription for the remaining keys: confirm via present-or-spent, racing timeout.
        let remainingKeys = (0 ..< publicKeys.count)
            .filter { !confirmed.contains($0) }
            .map { publicKeys[$0] }

        let anyRemainingPresent = try await raceCoinsSentOrClaimed(
            for: remainingKeys,
            blockTimeout: blockTimeout
        )

        return (anyPresentNow || anyRemainingPresent) ? .onChain : .alreadyClaimed
    }

    private func raceCoinsSentOrClaimed(for publicKeys: [Data], blockTimeout: UInt32) async throws -> Bool {
        let stream = acquireHeadStream()
        defer { releaseHeadStream() }

        logger?.debug("start, timeout \(blockTimeout) blocks")

        return try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { [logger] in
                var count: UInt32 = 0
                for try await header in stream.cancellable() {
                    count += 1
                    if count == 1 {
                        logger?.debug(
                            "started from block \(header.number.hexBlockNumber)"
                        )
                    }
                    if count >= blockTimeout {
                        throw CoinOnChainQueryError.timeout
                    }
                }
                throw CoinOnChainQueryError.subscriptionTerminated
            }

            group.addTask { [self] in
                try await coinOnChainQuery.awaitAllCoinsSentOrClaimed(for: publicKeys)
            }

            let result = try await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func acquireHeadStream() -> HeadsSharedStream {
        headsWaiterCount += 1
        guard let headsSharedStream else {
            let stream = blockNumberProvider.subscribeFinalizedHeads().share()
            headsSharedStream = stream
            return stream
        }
        return headsSharedStream
    }

    private func releaseHeadStream() {
        headsWaiterCount -= 1
        guard headsWaiterCount == 0 else {
            return
        }
        headsSharedStream = nil
    }
}

// MARK: - Claim Orchestration

private extension TransferRecipientService {
    struct PreparedEntry {
        let index: Int
        let privateKey: Data
        let senderPublicKey: Data
        let sourceCoin: OnChainCoin
        let destinationCoin: Coin
    }

    typealias SenderKey = (index: Int, privateKey: Data, publicKey: Data)
    typealias EntryFailure = (entryIndex: Int, error: Error)

    func claimAll(memo: TransferMemo, messageId: String) async -> ClaimReport {
        var failures: [EntryFailure] = []

        let senderKeys = deriveSenderKeys(from: memo, failures: &failures)

        let sourceCoins: [OnChainCoin?]
        do {
            sourceCoins = try await coinOnChainQuery.fetchCoins(for: senderKeys.map(\.publicKey))
        } catch {
            return ClaimReport(
                claimed: [],
                alreadyTransferred: [],
                externallySpent: 0,
                failures: senderKeys.map { ($0.index, error) } + failures
            )
        }

        let (prepared, externallySpent) = await allocateDestinations(
            senderKeys: senderKeys,
            sourceCoins: sourceCoins,
            failures: &failures
        )

        guard !prepared.isEmpty else {
            return ClaimReport(
                claimed: [],
                alreadyTransferred: [],
                externallySpent: externallySpent,
                failures: failures
            )
        }

        // Persist claim plan before submitting extrinsics
        let planEntries = prepared.map { entry in
            ClaimPlanEntry(
                entryIndex: entry.index,
                destinationCoin: entry.destinationCoin
            )
        }
        let plan = ClaimPlan(
            memoKey: memo.identifier(),
            messageId: messageId,
            entries: planEntries,
            totalValue: memo.totalValue
        )
        do {
            try await planStore.save(plan: plan)
            logger?.debug("Persisted claim plan with \(planEntries.count) entries")
        } catch {
            logger?.error("Failed to persist claim plan: \(error)")
        }

        let (claimed, transferFailures) = await submitTransfers(prepared)
        failures.append(contentsOf: transferFailures)

        return ClaimReport(
            claimed: claimed,
            alreadyTransferred: [],
            externallySpent: externallySpent,
            failures: failures
        )
    }

    /// Claims coins using pre-allocated destinations from an existing plan (avoids double allocation).
    ///
    /// Destination-first recovery: a transfer is "done" iff its destination coin exists on-chain,
    /// regardless of the source. Entries with a landed destination are reported as already
    /// transferred; the rest have their source coins fetched and are (re)submitted.
    func claimFromPlan(_ plan: ClaimPlan, memo: TransferMemo) async -> ClaimReport {
        let privateKeys = planPrivateKeys(plan: plan, memo: memo)

        // Entries whose destination coin already exists were completed by a prior run.
        let landedIndices = await landedDestinationIndices(plan.entries)
        let remaining = plan.entries.filter { !landedIndices.contains($0.entryIndex) }

        let (prepared, externallySpent) = await prepareTransfers(for: remaining, privateKeys: privateKeys)
        let (claimed, failures) = await submitTransfers(prepared)

        // A submit that fails but actually lands is not recovered here: its destination coin is not
        // yet finalized at this point. The entry stays in `failures`, the plan retries, and the next
        // run's `landedDestinationIndices` pass detects the now-finalized destination as completed.
        let alreadyTransferred = plan.entries
            .filter { landedIndices.contains($0.entryIndex) }
            .map(\.destinationCoin)

        return ClaimReport(
            claimed: claimed,
            alreadyTransferred: alreadyTransferred,
            externallySpent: externallySpent,
            failures: failures
        )
    }

    /// Maps each in-bounds plan entry to its memo private key.
    private func planPrivateKeys(plan: ClaimPlan, memo: TransferMemo) -> [Int: Data] {
        var result: [Int: Data] = [:]
        for entry in plan.entries where entry.entryIndex < memo.entries.count {
            result[entry.entryIndex] = memo.entries[entry.entryIndex]
        }
        return result
    }

    /// Returns the entry indices whose destination coin already exists on-chain (transfer complete).
    /// A single batch RPC; derivation failures are skipped (treated as not-yet-transferred).
    private func landedDestinationIndices(_ entries: [ClaimPlanEntry]) async -> Set<Int> {
        guard !entries.isEmpty else { return [] }

        var derivable: [(index: Int, publicKey: Data)] = []
        for entry in entries {
            guard let pubKey = try? coinKeyFactory.derivePublicKey(for: entry.destinationCoin) else {
                continue
            }
            derivable.append((entry.entryIndex, pubKey))
        }

        guard !derivable.isEmpty else { return [] }

        let coins = await (try? coinOnChainQuery.fetchCoins(for: derivable.map(\.publicKey))) ??
            Array(repeating: nil, count: derivable.count)

        var result: Set<Int> = []
        for (item, coin) in zip(derivable, coins) where coin != nil {
            result.insert(item.index)
        }
        return result
    }

    /// Fetches source coins for the given entries and builds submittable transfers.
    /// Entries with no derivable key or no on-chain source are dropped and counted as
    /// externally spent (source gone and destination absent ⇒ unrecoverable).
    private func prepareTransfers(
        for entries: [ClaimPlanEntry],
        privateKeys: [Int: Data]
    ) async -> (prepared: [PreparedEntry], externallySpent: Int) {
        var info: [(index: Int, privateKey: Data, publicKey: Data, destination: Coin)] = []
        for entry in entries {
            guard let privateKey = privateKeys[entry.entryIndex],
                  let publicKey = try? snKeyFactory.createPublicKey(fromSecret: privateKey).rawData() else {
                continue
            }
            info.append((entry.entryIndex, privateKey, publicKey, entry.destinationCoin))
        }

        guard !info.isEmpty else { return ([], entries.count) }

        let sourceCoins = await (try? coinOnChainQuery.fetchCoins(for: info.map(\.publicKey))) ??
            Array(repeating: nil, count: info.count)

        var prepared: [PreparedEntry] = []
        for (item, source) in zip(info, sourceCoins) {
            guard let source else { continue }
            prepared.append(PreparedEntry(
                index: item.index,
                privateKey: item.privateKey,
                senderPublicKey: item.publicKey,
                sourceCoin: source,
                destinationCoin: item.destination
            ))
        }

        return (prepared, entries.count - prepared.count)
    }

    /// Flips spent coins whose on-chain age has reached `coinMaxAge` back to `.available`
    /// locally and refreshes their stored age. Returns the total planks of restored coins.
    func restoreMaxAgeCoins(
        spentCoins: [Coin],
        sourceCoins: [OnChainCoin?],
        context: DenominationBreakdownContext
    ) async throws -> BigUInt {
        var coinsToRestore: [Coin] = []
        var totalPlanks: BigUInt = .zero

        for (spent, source) in zip(spentCoins, sourceCoins) {
            guard let source, source.age >= CoinageConstants.coinMaxAge else { continue }
            coinsToRestore.append(spent.changing(state: .available).changing(age: source.age))
            totalPlanks += context.valueInPlanks(for: spent.exponent)
        }

        if !coinsToRestore.isEmpty {
            try await coinService.save(coins: coinsToRestore)
            logger?.debug("Restored \(coinsToRestore.count) max-age spent coins to .available")
        }

        return totalPlanks
    }

    /// Drops entries already handled by `restoreMaxAgeCoins`. Externally-spent entries
    /// (nil source) stay so `allocateDestinations` can still count them.
    func filterTransferable(
        senderKeys: [SenderKey],
        sourceCoins: [OnChainCoin?]
    ) -> (keys: [SenderKey], sources: [OnChainCoin?]) {
        var keys: [SenderKey] = []
        var sources: [OnChainCoin?] = []

        for (key, source) in zip(senderKeys, sourceCoins) {
            if let source, source.age >= CoinageConstants.coinMaxAge {
                continue
            }
            keys.append(key)
            sources.append(source)
        }

        return (keys, sources)
    }

    func deriveSenderKeys(from memo: TransferMemo, failures: inout [EntryFailure]) -> [SenderKey] {
        var senderKeys: [SenderKey] = []
        for (index, privateKey) in memo.entries.enumerated() {
            do {
                let pubKey = try snKeyFactory.createPublicKey(fromSecret: privateKey).rawData()
                senderKeys.append((index, privateKey, pubKey))
            } catch {
                failures.append((index, error))
            }
        }
        return senderKeys
    }

    func allocateDestinations(
        senderKeys: [SenderKey],
        sourceCoins: [OnChainCoin?],
        failures: inout [EntryFailure]
    ) async -> (prepared: [PreparedEntry], externallySpent: Int) {
        var prepared: [PreparedEntry] = []
        var externallySpent = 0

        for (entry, optCoin) in zip(senderKeys, sourceCoins) {
            guard let sourceCoin = optCoin else {
                externallySpent += 1
                continue
            }

            do {
                let newCoin = try await coinAllocator.allocate(exponent: Int16(sourceCoin.value))
                prepared.append(PreparedEntry(
                    index: entry.index,
                    privateKey: entry.privateKey,
                    senderPublicKey: entry.publicKey,
                    sourceCoin: sourceCoin,
                    destinationCoin: newCoin
                ))
            } catch {
                failures.append((entry.index, error))
            }
        }

        return (prepared, externallySpent)
    }

    func submitTransfers(
        _ entries: [PreparedEntry]
    ) async -> (claimed: [Coin], failures: [EntryFailure]) {
        var claimed: [Coin] = []
        var failures: [EntryFailure] = []

        await withTaskGroup(of: (Int, Result<Coin, Error>).self) { group in
            for entry in entries {
                group.addTask { [transferSubmitter, logger] in
                    do {
                        let coin = try await transferSubmitter.submitTransfer(
                            senderPrivateKey: entry.privateKey,
                            senderPublicKey: entry.senderPublicKey,
                            destinationCoin: entry.destinationCoin
                        )
                        logger?.debug("Transfer extrinsic succeeded for entry \(entry.index)")
                        return (entry.index, .success(coin))
                    } catch {
                        logger?.error("Transfer extrinsic failed for entry \(entry.index): \(error)")
                        return (entry.index, .failure(error))
                    }
                }
            }

            for await (index, result) in group {
                switch result {
                case let .success(coin):
                    claimed.append(coin)
                case let .failure(error):
                    failures.append((index, error))
                }
            }
        }

        return (claimed, failures)
    }
}

private extension String {
    /// Decodes a hex-encoded block number (e.g. a header's `number` field) into a decimal string.
    /// Falls back to the raw hex when the value is not valid hex or overflows `UInt32`.
    var hexBlockNumber: String {
        BigUInt.fromHexString(self).flatMap { UInt32(exactly: $0) }.map(String.init) ?? self
    }
}
