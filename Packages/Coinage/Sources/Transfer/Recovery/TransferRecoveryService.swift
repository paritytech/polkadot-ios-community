import AsyncExtensions
import Foundation
import SDKLogger
import SubstrateSdk
import SubstrateStorageQuery
import KeyDerivation
import StructuredConcurrency
import ExtrinsicService
import SubstrateOperation

public enum RecoveryStatus {
    case idle
    case recovering
    case completed
    case failed(Error)
}

public protocol TransferRecoveryServicing: Actor {
    /// Runs recovery. Must complete before sync services start.
    func recover() async
}

/// Startup recovery orchestrator for transfer WAL entries.
///
/// Subscribes to `chain_subscribeFinalizedHeads` immediately on startup. Substrate sends the
/// current finalized head as the first emission.
/// Each emission resolves all pending WAL entries in parallel against the finalized state.
///
/// Resolution per entry:
/// - Output coins found at finalized hash → write coins, mark inputs spent, delete WAL
/// - Output coins not found + inputs consumed → mark inputs spent, delete WAL (recipient claimed outputs)
/// - Output coins not found + `currentFinalizedBlock > checkpointBlockNumber + mortality` → revert inputs
/// - Output coins not found + `checkpointBlockNumber == .max` → treat as expired, revert immediately
/// - Output coins not found + within mortality → leave pending, retry on next finalized block
///
/// Exits when all WAL entries are resolved, then runs orphaned pending asset recovery.
public actor TransferRecoveryService {
    private let walStore: any TransferWALStoring
    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol
    private let coinQuery: any CoinOnChainQuerying
    private let voucherQuery: any VoucherOnChainQuerying
    private let coinKeyFactory: any CoinKeyDeriving
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let blockNumberProvider: any BlockInfoProviding
    private let logger: SDKLoggerProtocol?

    private nonisolated let statusSubject = AsyncCurrentValueSubject<RecoveryStatus>(.idle)
    private var isRecovering = false

    public nonisolated var statusStream: AnyAsyncSequence<RecoveryStatus> {
        statusSubject.eraseToAnyAsyncSequence()
    }

    init(
        walStore: any TransferWALStoring,
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol,
        coinQuery: any CoinOnChainQuerying,
        voucherQuery: any VoucherOnChainQuerying,
        coinKeyFactory: any CoinKeyDeriving,
        voucherKeyFactory: any VoucherKeyDeriving,
        blockNumberProvider: any BlockInfoProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.walStore = walStore
        self.coinService = coinService
        self.voucherService = voucherService
        self.coinQuery = coinQuery
        self.voucherQuery = voucherQuery
        self.coinKeyFactory = coinKeyFactory
        self.voucherKeyFactory = voucherKeyFactory
        self.blockNumberProvider = blockNumberProvider
        self.logger = logger
    }
}

extension TransferRecoveryService: TransferRecoveryServicing {
    /// Runs recovery. Must complete before sync services start.
    ///
    /// Subscribes to `chain_subscribeFinalizedHeads` immediately — the first emission is the
    /// current finalized head. Each subsequent emission re-resolves remaining WAL entries.
    /// Exits when all entries resolved or timeout reached.
    /// After WAL resolution, recovers orphaned pending assets that have no WAL entry.
    public func recover() async {
        guard !isRecovering else {
            logger?.warning("Already recovering, skipping")
            return
        }
        isRecovering = true
        defer { isRecovering = false }

        statusSubject.send(.recovering)

        do {
            logger?.debug("Starting recovery")

            let walEntries = try await walStore.fetchAll()

            // Build sets of coin and voucher IDs covered by WAL entries
            let walCoveredCoinIds = Set(walEntries.flatMap(\.inputCoinIds))
            let walCoveredVoucherIds = Set(walEntries.flatMap(\.inputVoucherIds))
            let walCoveredSurplusVoucherIds = Set(
                walEntries.flatMap(\.expectedVoucherIndices).map { "\($0)" }
            )

            if !walEntries.isEmpty {
                logger?.debug("Found \(walEntries.count) WAL entries")
                try await recover(walEntries: walEntries)
            }

            // Recover orphaned pending assets that have no WAL entry.
            // WAL-covered assets are already resolved before orphan recovery runs,
            // preventing double-processing.
            try await recoverOrphanedPendingAssets(
                walCoveredCoinIds: walCoveredCoinIds,
                walCoveredVoucherIds: walCoveredVoucherIds,
                walCoveredSurplusVoucherIds: walCoveredSurplusVoucherIds
            )

            logger?.debug("Recovery completed")
            statusSubject.send(.completed)
        } catch {
            logger?.error("Recovery failed: \(error)")
            statusSubject.send(.failed(error))
        }
    }
}

extension TransferRecoveryService {
    /// Subscription loop driven by `chain_subscribeFinalizedHeads`.
    ///
    /// First emission = current finalized head (Substrate sends it immediately on subscribe),
    /// so this handles both the initial check and ongoing monitoring in a single loop.
    /// Exits when all entries resolved.
    private func recover(walEntries: [TransferWALEntry]) async throws {
        var pendingEntries = walEntries
        let headersStream = blockNumberProvider.subscribeFinalizedHeads()

        for try await header in headersStream {
            guard let finalizedBlock = header.blockNumber else {
                logger?.warning("Could not parse block number from finalized head, skipping")
                continue
            }

            let finalizedHash = try await blockNumberProvider.fetchBlockHash(finalizedBlock)

            logger?.debug("Finalized block \(finalizedBlock), resolving \(pendingEntries.count) entries")

            var resolved: [UUID] = []
            try await withThrowingTaskGroup(of: UUID?.self) { group in
                for entry in pendingEntries {
                    group.addTask {
                        try await self.resolveWALEntry(
                            entry,
                            atBlockHash: finalizedHash,
                            finalizedBlock: finalizedBlock
                        ) ? entry.id : nil
                    }
                }
                for try await id in group {
                    if let id { resolved.append(id) }
                }
            }

            pendingEntries.removeAll { resolved.contains($0.id) }
            logger?.debug("Resolved \(resolved.count), \(pendingEntries.count) remaining")

            guard pendingEntries.isEmpty else { continue }
            return
        }
    }
}

extension TransferRecoveryService {
    /// Resolves a single WAL entry against on-chain state at a specific finalized block hash.
    ///
    /// Returns `true` if the entry was resolved (deleted from WAL), `false` if left pending.
    /// Dispatches to type-specific resolution based on ``TransferOperationType``.
    private func resolveWALEntry(
        _ entry: TransferWALEntry,
        atBlockHash: BlockHashData,
        finalizedBlock: UInt32
    ) async throws -> Bool {
        logger?
            .debug("Resolving WAL entry \(entry.id) (\(entry.operationType)) at block \(atBlockHash.toHexWithPrefix())")

        switch entry.operationType {
        case .intoCoins:
            return try await resolveIntoCoins(entry, atBlockHash: atBlockHash, finalizedBlock: finalizedBlock)
        case .intoExternalAsset:
            return try await resolveIntoExternalAsset(entry, atBlockHash: atBlockHash, finalizedBlock: finalizedBlock)
        }
    }

    /// Resolves an `.intoCoins` WAL entry by checking expected output coins on-chain.
    ///
    /// - Coins found → write locally, mark inputs spent, delete WAL
    /// - Coins not found + inputs consumed → mark inputs spent, delete WAL
    /// - Coins not found + expired → revert inputs, delete WAL
    /// - Coins not found + within mortality → leave pending
    private func resolveIntoCoins(
        _ entry: TransferWALEntry,
        atBlockHash: BlockHashData,
        finalizedBlock: UInt32
    ) async throws -> Bool {
        guard !entry.expectedCoinIndices.isEmpty else {
            logger?.debug("WAL entry \(entry.id): no expected indices, deleting")
            try await walStore.delete(id: entry.id)
            return true
        }

        let probeKeys = try entry.expectedCoinIndices.map {
            try coinKeyFactory.derivePublicKey(placeholderIndex: $0)
        }
        let onChainResults = try await coinQuery.fetchCoins(for: probeKeys, atBlockHash: atBlockHash)

        if onChainResults.contains(where: { $0 != nil }) {
            logger?.debug("WAL entry \(entry.id): confirmed on-chain, writing coins")
            try await writeConfirmedCoins(for: entry, onChainResults: onChainResults)
            try await markInputsSpent(for: entry)
            try await walStore.delete(id: entry.id)
            return true
        }

        let inputsConsumed = try await checkInputsConsumed(for: entry, atBlockHash: atBlockHash)
        if inputsConsumed {
            logger?.debug("WAL entry \(entry.id): inputs consumed (recipient claimed), marking spent")
            try await markInputsSpent(for: entry)
            try await walStore.delete(id: entry.id)
            return true
        }

        return try await resolveByExpiry(entry, finalizedBlock: finalizedBlock)
    }

    /// Resolves an `.intoExternalAsset` WAL entry by verifying input vouchers
    /// are consumed on-chain and surplus vouchers appeared on-chain.
    ///
    /// - Inputs consumed → mark inputs spent, confirm surplus vouchers, delete WAL
    /// - Inputs still present + expired → revert inputs, delete surplus vouchers, delete WAL
    /// - Inputs still present + within mortality → leave pending
    private func resolveIntoExternalAsset(
        _ entry: TransferWALEntry,
        atBlockHash: BlockHashData,
        finalizedBlock: UInt32
    ) async throws -> Bool {
        let inputsConsumed = try await checkInputsConsumed(for: entry, atBlockHash: atBlockHash)
        if inputsConsumed {
            logger?.debug("WAL entry \(entry.id): vouchers consumed on-chain, marking spent")
            try await markInputsSpent(for: entry)
            try await confirmSurplusVouchers(for: entry, atBlockHash: atBlockHash)
            try await walStore.delete(id: entry.id)
            return true
        }

        return try await resolveByExpiry(entry, finalizedBlock: finalizedBlock)
    }

    /// Queries chain for expected surplus vouchers and marks them available locally.
    /// If vouchers are not found on-chain (edge case), they stay as pendingOnboarding
    /// and will be cleaned up by orphaned recovery on the next cycle.
    private func confirmSurplusVouchers(
        for entry: TransferWALEntry,
        atBlockHash: BlockHashData
    ) async throws {
        guard !entry.expectedVoucherIndices.isEmpty else { return }

        let onChainResults = try await voucherQuery.fetchVouchers(
            for: entry.expectedVoucherIndices,
            atBlockHash: atBlockHash
        )

        let confirmedIds = zip(entry.expectedVoucherIndices, onChainResults)
            .filter { $0.1 != nil }
            .map { "\($0.0)" }

        if !confirmedIds.isEmpty {
            try await voucherService.markAvailable(identifiers: confirmedIds)
            logger?.debug("WAL entry \(entry.id): confirmed \(confirmedIds.count) surplus vouchers")
        }
    }

    /// Shared expiry check: reverts if expired, leaves pending if within mortality.
    private func resolveByExpiry(
        _ entry: TransferWALEntry,
        finalizedBlock: UInt32
    ) async throws -> Bool {
        let expired = try await isExtrinsicExpired(entry, finalizedBlock: finalizedBlock)
        guard expired else {
            logger?.debug("WAL entry \(entry.id): within mortality window, leaving pending")
            return false
        }
        logger?.debug("WAL entry \(entry.id): expired, reverting inputs")
        try await revertEntry(entry)
        return true
    }

    /// Saves locally the output coins already confirmed on-chain.
    ///
    /// `onChainResults` is the result of the probe fetch in `resolveWALEntry` — reused here
    /// to avoid a redundant RPC call. The actual exponent is read from `OnChainCoin.value: Int8`.
    private func writeConfirmedCoins(
        for entry: TransferWALEntry,
        onChainResults: [CoinSyncResult.OnChainCoin?]
    ) async throws {
        var coinsToSave: [Coin] = []
        for (index, onChainCoin) in zip(entry.expectedCoinIndices, onChainResults) {
            guard let coin = onChainCoin else { continue }
            coinsToSave.append(
                Coin(exponent: Int16(coin.value), derivationIndex: index, age: coin.age)
            )
        }

        try await coinService.save(coins: coinsToSave)
    }

    private func markInputsSpent(for entry: TransferWALEntry) async throws {
        if !entry.inputCoinIds.isEmpty {
            try await coinService.markSpent(coinIds: entry.inputCoinIds)
        }
        if !entry.inputVoucherIds.isEmpty {
            try await voucherService.delete(identifiers: entry.inputVoucherIds)
        }
    }

    /// Returns `true` when all parseable input coins and vouchers are absent on-chain at
    /// the specified block hash, indicating the transfer extrinsic confirmed and inputs were consumed.
    ///
    /// Returns `false` when any input is still present (transfer did not confirm) or when
    /// no valid derivation indices can be parsed (conservative: treat as unconfirmed).
    ///
    /// Coin and voucher RPC queries run in parallel.
    private func checkInputsConsumed(for entry: TransferWALEntry, atBlockHash: BlockHashData) async throws -> Bool {
        let coinIndices = entry.inputCoinIds.compactMap { UInt32($0) }
        let voucherIndices = entry.inputVoucherIds.compactMap { UInt32($0) }

        guard !coinIndices.isEmpty || !voucherIndices.isEmpty else {
            return false
        }

        async let coinResults: [CoinSyncResult.OnChainCoin?] = {
            guard !coinIndices.isEmpty else { return [] }
            let keys = try coinIndices.map {
                try coinKeyFactory.derivePublicKey(placeholderIndex: $0)
            }
            return try await coinQuery.fetchCoins(for: keys, atBlockHash: atBlockHash)
        }()

        async let voucherResults: [VoucherOnChainInfo?] = {
            guard !voucherIndices.isEmpty else { return [] }
            return try await voucherQuery.fetchVouchers(for: voucherIndices, atBlockHash: atBlockHash)
        }()

        let (coins, vouchers) = try await (coinResults, voucherResults)
        return coins.allSatisfy { $0 == nil } && vouchers.allSatisfy { $0 == nil }
    }

    /// Returns `true` when the extrinsic's mortality window has definitely closed.
    ///
    /// Uses finalized block number to avoid reverting transactions that are still valid
    /// after a best-chain reorg.
    ///
    /// `checkpointBlockNumber == .max` means the extrinsic hash was never reported — the
    /// extrinsic was never broadcast (submission failed or app crashed before the hash callback).
    /// It is NOT an immortal transaction sentinel. Treat as expired so the entry can be
    /// reverted immediately with no double-spend risk.
    ///
    /// `finalizedBlock` is supplied by the caller when available (parsed from the finalized
    /// header subscription) to avoid an extra RPC round-trip. Falls back to `blockNumberProvider`
    /// only when nil.
    ///
    /// Block comparison handles UInt32 overflow by converting to UInt64 before adding
    /// the mortality window.
    private func isExtrinsicExpired(_ entry: TransferWALEntry, finalizedBlock: UInt32) async throws -> Bool {
        guard case let .known(checkpointNumber, checkpointHash) = entry.checkpointBlock else {
            // `.pending` means the extrinsic was never broadcast — revert immediately.
            return true
        }

        // Verify the birth block is still canonical.
        // A forked checkpoint means the extrinsic is permanently invalid regardless of mortality.
        let canonicalHash = try await blockNumberProvider.fetchBlockHash(checkpointNumber)
        guard canonicalHash == checkpointHash else {
            logger?.debug(
                "WAL entry \(entry.id): checkpoint block \(checkpointNumber) was forked, treating as expired"
            )
            return true
        }

        // Use UInt64 to avoid overflow when adding mortality window.
        let expiryBlock = UInt64(checkpointNumber) + UInt64(entry.mortality)
        return UInt64(finalizedBlock) > expiryBlock
    }

    private func revertEntry(_ entry: TransferWALEntry) async throws {
        if !entry.inputCoinIds.isEmpty {
            try await coinService.markAvailable(coinIds: entry.inputCoinIds)
        }
        if !entry.inputVoucherIds.isEmpty {
            try await voucherService.markAvailable(identifiers: entry.inputVoucherIds)
        }
        // Delete surplus vouchers that were never minted on-chain
        if !entry.expectedVoucherIndices.isEmpty {
            let surplusIds = entry.expectedVoucherIndices.map { "\($0)" }
            try await voucherService.delete(identifiers: surplusIds)
        }
        try await walStore.delete(id: entry.id)
    }
}

// MARK: - Orphaned pending recovery

extension TransferRecoveryService {
    /// Resolves `pendingTransfer` assets that have no WAL entry.
    ///
    /// The WAL entry is written immediately before extrinsic broadcast. If the app crashes
    /// after `markPendingTransfer` but before `walStore.save`, the asset is stuck
    /// `pendingTransfer` with no WAL entry and no handler to clear it.
    ///
    /// Because the WAL was never written, the extrinsic was never submitted — the asset
    /// is still valid on-chain and can be unconditionally restored without querying the chain.
    ///
    /// Must run after WAL-based recovery so WAL-covered assets are already resolved
    /// and not double-processed here.
    private func recoverOrphanedPendingAssets(
        walCoveredCoinIds: Set<String>,
        walCoveredVoucherIds: Set<String>,
        walCoveredSurplusVoucherIds: Set<String>
    ) async throws {
        let allCoins = try await coinService.fetchAllCoins()
        let pendingCoinIds = Set(
            allCoins
                .filter { $0.state == .pendingTransfer }
                .map(\.identifier)
        )
        let orphanedCoinIds = pendingCoinIds.subtracting(walCoveredCoinIds)

        if !orphanedCoinIds.isEmpty {
            logger?.debug("Orphaned pending coins: restoring \(orphanedCoinIds.count) to available")
            try await coinService.markAvailable(coinIds: Array(orphanedCoinIds))
        }

        let allVouchers = try await voucherService.fetchAll()

        // Orphaned pendingTransfer vouchers: extrinsic never submitted, restore to available
        let pendingVoucherIds = Set(
            allVouchers
                .filter { $0.localState == .pendingTransfer }
                .map(\.identifier)
        )
        let orphanedVoucherIds = pendingVoucherIds.subtracting(walCoveredVoucherIds)

        if !orphanedVoucherIds.isEmpty {
            logger?.debug("Orphaned pending vouchers: restoring \(orphanedVoucherIds.count) to available")
            try await voucherService.markAvailable(identifiers: Array(orphanedVoucherIds))
        }

        // Orphaned pendingOnboarding vouchers: surplus vouchers saved before submission
        // but no WAL entry → extrinsic never submitted, vouchers never minted on-chain → delete
        let pendingOnboardingIds = Set(
            allVouchers
                .filter { $0.localState == .pendingOnboarding }
                .map(\.identifier)
        )
        let orphanedOnboardingIds = pendingOnboardingIds.subtracting(walCoveredSurplusVoucherIds)

        if !orphanedOnboardingIds.isEmpty {
            logger?.debug("Orphaned pendingOnboarding vouchers: deleting \(orphanedOnboardingIds.count)")
            try await voucherService.delete(identifiers: Array(orphanedOnboardingIds))
        }
    }
}

// MARK: -

private extension Block.Header {
    var blockNumber: UInt32? {
        if number.hasPrefix("0x") {
            UInt32(number.dropFirst(2), radix: 16)
        } else {
            UInt32(number, radix: 16)
        }
    }
}
