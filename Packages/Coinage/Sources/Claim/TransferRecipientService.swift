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

    /// Revokes spent coins by deriving public keys from secret keys and transferring
    /// them to new destinations, without persisting a claim plan.
    /// This is used for user-initiated recovery of locally-spent coins that may still
    /// be claimable on-chain.
    /// Returns the total planks of successfully revoked coins.
    func revokeFromSecretKeys(
        secretKeys: [Data],
        context: DenominationBreakdownContext
    ) async throws -> BigUInt
}

/// Waits until outgoing transfer coins have appeared on-chain, or throws on timeout.
public protocol TransferSendVerifying: Actor {
    func awaitSendOnChain(memo: TransferMemo, blockTimeout: UInt32) async throws
    func awaitClaimOnChain(memo: TransferMemo, blockTimeout: UInt32) async throws
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
            "Claim completed - claimed: \(report.claimed.count), already transferred: \(report.alreadyTransferred.count)"
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

    func revokeFromSecretKeys(
        secretKeys: [Data],
        context: DenominationBreakdownContext
    ) async throws -> BigUInt {
        guard !secretKeys.isEmpty else { return .zero }

        let senderKeys = try secretKeys.enumerated().map { index, privateKey in
            let publicKey = try snKeyFactory.createPublicKey(fromSecret: privateKey).rawData()
            return (index: index, privateKey: privateKey, publicKey: publicKey)
        }

        let sourceCoins = try await coinOnChainQuery.fetchCoins(for: senderKeys.map(\.publicKey))

        var failures: [EntryFailure] = []
        let (prepared, _) = await allocateDestinations(
            senderKeys: senderKeys,
            sourceCoins: sourceCoins,
            failures: &failures
        )

        guard !prepared.isEmpty else { return .zero }

        let (claimed, submitFailures) = await submitTransfers(prepared)
        failures.append(contentsOf: submitFailures)

        if !claimed.isEmpty {
            try await coinService.save(coins: claimed)
            logger?.debug("Saved \(claimed.count) revoked coins")
        }

        if !failures.isEmpty {
            logger?.error("Revoke had \(failures.count) failures")
        }

        let total = claimed.reduce(.zero) { $0 + context.valueInPlanks(for: $1.exponent) }
        return total
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

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var count: UInt32 = 0
                for try await _ in stream {
                    count += 1
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

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var count: UInt32 = 0
                for try await _ in stream {
                    count += 1
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
    /// Derives all sender keys synchronously, then batch-fetches source coins in a single RPC call.
    /// Entries whose source coins are already spent are checked for existing destination coins
    /// (indicating a previously completed transfer).
    func claimFromPlan(_ plan: ClaimPlan, memo: TransferMemo) async -> ClaimReport {
        /// A plan entry enriched with derived sender key pair for batch processing.
        struct ValidEntry {
            let planEntry: ClaimPlanEntry
            let privateKey: Data
            let publicKey: Data
        }

        let validEntries: [ValidEntry] = plan.entries.compactMap { entry in
            guard entry.entryIndex < memo.entries.count else { return nil }
            let privateKey = memo.entries[entry.entryIndex]
            guard let publicKey = try? snKeyFactory.createPublicKey(fromSecret: privateKey).rawData() else {
                return nil
            }
            return ValidEntry(
                planEntry: entry,
                privateKey: privateKey,
                publicKey: publicKey
            )
        }

        // Batch-fetch all source coins in a single RPC call
        let sourceCoins = await (try? coinOnChainQuery.fetchCoins(for: validEntries.map(\.publicKey))) ??
            Array(repeating: nil, count: validEntries.count)

        // Match results back by index
        var prepared: [PreparedEntry] = []
        for (entry, sourceCoin) in zip(validEntries, sourceCoins) {
            guard let sourceCoin else { continue }

            prepared.append(PreparedEntry(
                index: entry.planEntry.entryIndex,
                privateKey: entry.privateKey,
                senderPublicKey: entry.publicKey,
                sourceCoin: sourceCoin,
                destinationCoin: entry.planEntry.destinationCoin
            ))
        }

        guard !prepared.isEmpty else {
            // All source coins are gone — check if destination coins already exist on-chain
            let alreadyTransferred = await findExistingDestinationCoins(plan: plan)
            return ClaimReport(
                claimed: [],
                alreadyTransferred: alreadyTransferred,
                externallySpent: plan.entries.count - alreadyTransferred.count,
                failures: []
            )
        }

        var failures: [EntryFailure] = []
        let (claimed, transferFailures) = await submitTransfers(prepared)
        failures.append(contentsOf: transferFailures)

        // Also check destination coins for entries where source is gone
        let preparedIndices = Set(prepared.map(\.index))
        let alreadyTransferred = await findExistingDestinationCoins(
            plan: plan,
            excludingIndices: preparedIndices
        )

        return ClaimReport(
            claimed: claimed,
            alreadyTransferred: alreadyTransferred,
            externallySpent: 0,
            failures: failures
        )
    }

    /// Batch-checks which destination coins from a plan already exist on-chain.
    ///
    /// Derives all destination public keys, then performs a single RPC batch query.
    /// Returns coins whose on-chain counterparts were found (indicating completed transfers).
    ///
    /// - Parameters:
    ///   - plan: The claim plan containing destination coin allocations.
    ///   - excludingIndices: Entry indices to skip (e.g. entries already handled via `submitTransfers`).
    private func findExistingDestinationCoins(
        plan: ClaimPlan,
        excludingIndices: Set<Int> = []
    ) async -> [Coin] {
        let entriesToCheck = plan.entries.filter { !excludingIndices.contains($0.entryIndex) }
        guard !entriesToCheck.isEmpty else { return [] }

        // Derive all destination public keys, tracking which entries succeeded
        var derivedEntries: [(entry: ClaimPlanEntry, publicKey: Data)] = []
        for entry in entriesToCheck {
            guard let pubKey = try? coinKeyFactory.derivePublicKey(for: entry.destinationCoin) else {
                continue
            }
            derivedEntries.append((entry, pubKey))
        }

        guard !derivedEntries.isEmpty else { return [] }

        // Single batch fetch
        let coins = await (try? coinOnChainQuery.fetchCoins(for: derivedEntries.map(\.publicKey))) ??
            Array(repeating: nil, count: derivedEntries.count)

        // Collect entries whose destination coin exists on-chain
        return zip(derivedEntries, coins).compactMap { tuple, coin in
            coin != nil ? tuple.entry.destinationCoin : nil
        }
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
