import Foundation
import ExtrinsicService
import StructuredConcurrency
import SubstrateSdk
import SubstrateSdkExt
import KeyDerivation
import BigInt
import SDKLogger
import SubstrateOperation

/// Strategy 3: Unload vouchers directly into required denominations.
///
/// Submits one extrinsic per recycler group. `CoinSelector` guarantees each group
/// respects the `maxConsolidation` pallet constraint (throws if exceeded). All groups
/// run concurrently — one task per `RecyclerKey`.
struct UnloadIntoCoinsStrategy {
    private let readyCoins: [Coin]
    private let perGroupCoins: [RecyclerGroupCoins]
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let recyclerLoader: RecyclerReadinessLoading
    private let coinKeyFactory: any CoinKeyDeriving
    private let coordinator: any ExtrinsicSubmissionCoordinating
    private let originFactory: OriginCreating
    private let walStore: any TransferWALStoring
    private let mortality: UInt32
    private let blockInfoProvider: any BlockInfoProviding
    private let currentDate: Date
    private let logger: SDKLoggerProtocol?

    init(
        readyCoins: [Coin],
        perGroupCoins: [RecyclerGroupCoins],
        voucherKeyFactory: any VoucherKeyDeriving,
        recyclerLoader: RecyclerReadinessLoading,
        coinKeyFactory: any CoinKeyDeriving,
        coordinator: any ExtrinsicSubmissionCoordinating,
        originFactory: OriginCreating,
        walStore: any TransferWALStoring,
        mortality: UInt32,
        blockInfoProvider: any BlockInfoProviding,
        currentDate: Date,
        logger: SDKLoggerProtocol?
    ) {
        self.readyCoins = readyCoins
        self.perGroupCoins = perGroupCoins
        self.voucherKeyFactory = voucherKeyFactory
        self.coinKeyFactory = coinKeyFactory
        self.recyclerLoader = recyclerLoader
        self.coordinator = coordinator
        self.originFactory = originFactory
        self.walStore = walStore
        self.mortality = mortality
        self.blockInfoProvider = blockInfoProvider
        self.currentDate = currentDate
        self.logger = logger
    }
}

// MARK: - TransferStrategy

extension UnloadIntoCoinsStrategy: TransferStrategy {
    func run(context: TransferContext) async throws {
        guard !perGroupCoins.isEmpty else {
            throw TransferStrategyError.emptyVouchers
        }

        let allVouchers = perGroupCoins.flatMap(\.vouchers)

        guard !allVouchers.contains(where: { $0.recycler == nil }) else {
            throw TransferStrategyError.missingRecyclerInfo
        }

        // Fetch finalized block hash upfront to ensure both operations query the same state
        let blockHash = try await blockInfoProvider.fetchCurrentHash()

        // Create all origins upfront — each group needs a distinct unload token.
        let origins = try await originFactory.createAsUnloadTokenOrigins(
            voucherGroups: perGroupCoins.map(\.vouchers),
            currentDate: currentDate,
            blockHash: blockHash
        )

        logger?.info(
            "Submitting \(perGroupCoins.count) unload extrinsics for \(allVouchers.count) vouchers"
        )

        let keys = perGroupCoins.map(\.recyclerKey)
        let revisions = try await recyclerLoader.fetchRevisions(for: keys, blockHash: blockHash)

        guard keys.count == revisions.count else {
            assertionFailure("Revision for recyclerKey is missing")
            throw TransferStrategyError.invalidRecyclerRevision
        }

        // Build WAL entries for all groups before launching the task group.
        // All entries must be persisted before any extrinsic is broadcast.
        var walEntriesByKey: [RecyclerKey: TransferWALEntry] = [:]
        for groupCoins in perGroupCoins {
            let expectedIndices = (groupCoins.recipientCoins + groupCoins.changeCoins)
                .map(\.derivationIndex)
            let entry = TransferWALEntry(
                inputCoinIds: [],
                inputVoucherIds: groupCoins.vouchers.map(\.identifier),
                expectedCoinIndices: expectedIndices,
                mortality: mortality
            )
            walEntriesByKey[groupCoins.recyclerKey] = entry
        }
        try await walStore.save(contentsOf: Array(walEntriesByKey.values))

        // Capture dependencies explicitly so self is not captured in @Sendable task closures.
        let coord = coordinator
        let voucherFactory = voucherKeyFactory
        let coinFactory = coinKeyFactory
        let groupLogger = logger

        // Non-throwing task group — a failure in one group must not discard already-committed
        // results from other groups. Each group maps to exactly one RecyclerKey.
        typealias GroupResult = Result<([Voucher], [Coin], [Coin], UUID), Error>

        let allResults: [GroupResult] = await withTaskGroup(of: GroupResult.self) { taskGroup in
            for (groupCoins, origin) in zip(perGroupCoins, origins) {
                let revision = revisions[groupCoins.recyclerKey]! // validated above
                let walEntryId = walEntriesByKey[groupCoins.recyclerKey]!.id

                taskGroup.addTask {
                    do {
                        let value = try await processItem(
                            groupCoins: groupCoins,
                            origin: origin,
                            revision: revision,
                            walEntryId: walEntryId,
                            voucherKeyFactory: voucherFactory,
                            coinKeyFactory: coinFactory,
                            coordinator: coord,
                            logger: groupLogger
                        )
                        return .success((value.0, value.1, value.2, walEntryId))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var results: [GroupResult] = []
            for await result in taskGroup {
                results.append(result)
            }
            return results
        }

        // Record all on-chain changes locally before surfacing errors.
        // Each group's WAL entry is deleted after context.process().
        var collectedErrors: [Error] = []
        for groupResult in allResults {
            switch groupResult {
            case let .success((spentVouchers, changeCoins, destinationCoins, walEntryId)):
                do {
                    logger?.info("Unload complete successfully")
                    try await context.process(
                        spentVouchers: spentVouchers,
                        change: changeCoins,
                        destinationCoins: destinationCoins
                    )
                    try await walStore.delete(id: walEntryId)
                } catch {
                    logger?.error("Failed to record unload locally: \(error)")
                    collectedErrors.append(error)
                }
            case let .failure(error):
                logger?.error("Unload task failed: \(error)")
                collectedErrors.append(error)
            }
        }

        // Process ready coins regardless of extrinsic errors — they require no on-chain submission.
        if !readyCoins.isEmpty {
            do {
                try await context.process(spentCoins: readyCoins, destinationCoins: [])
            } catch {
                logger?.error("Failed to record ready coins locally: \(error)")
                collectedErrors.append(error)
            }
        }

        guard collectedErrors.isEmpty else {
            throw TransferStrategyError.multiple(collectedErrors)
        }
    }
}

// MARK: - Private Helpers

private extension UnloadIntoCoinsStrategy {
    func buildCall(
        for groupCoins: RecyclerGroupCoins,
        revision: UInt32,
        voucherKeyFactory: any VoucherKeyDeriving,
        coinKeyFactory: any CoinKeyDeriving
    ) throws -> CoinagePallet.Calls.UnloadRecyclerIntoCoins {
        let key = groupCoins.recyclerKey

        let aliases = try groupCoins.vouchers.map {
            try voucherKeyFactory.createKeyManager(for: $0)
                .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
        }

        var destGrouped: [Int16: [Data]] = [:]
        for coin in groupCoins.recipientCoins + groupCoins.changeCoins {
            let accountId = try coinKeyFactory.derivePublicKey(for: coin)
            destGrouped[coin.exponent, default: []].append(accountId)
        }
        let destinations = destGrouped.map { exponent, accounts in
            CoinagePallet.Calls.Split.SplitDestination(exponent: exponent, accounts: accounts)
        }

        return CoinagePallet.Calls.UnloadRecyclerIntoCoins(
            aliases: aliases,
            value: Int8(key.exponent),
            index: key.index,
            revision: revision,
            splitInto: destinations.sorted { $0.exponent < $1.exponent }
        )
    }

    func processItem(
        groupCoins: RecyclerGroupCoins,
        origin: any ExtrinsicOriginDefining,
        revision: UInt32,
        walEntryId: UUID,
        voucherKeyFactory: any VoucherKeyDeriving,
        coinKeyFactory: any CoinKeyDeriving,
        coordinator: any ExtrinsicSubmissionCoordinating,
        logger: SDKLoggerProtocol?
    ) async throws -> (spentVouchers: [Voucher], changeCoins: [Coin], destinationCoins: [Coin]) {
        let key = groupCoins.recyclerKey

        let call = try buildCall(
            for: groupCoins,
            revision: revision,
            voucherKeyFactory: voucherKeyFactory,
            coinKeyFactory: coinKeyFactory
        )

        let submission = try await coordinator.submit(
            walEntryId: walEntryId,
            builder: { try $0.adding(call: call.callAsFunction()) },
            origin: origin
        )

        switch submission.status {
        case .success:
            logger?.debug("Unload extrinsic succeeded for key \(key)")
            return (groupCoins.vouchers, groupCoins.changeCoins, groupCoins.recipientCoins)
        case let .failure(error):
            logger?.error("Unload extrinsic failed for key \(key): \(error.error)")
            throw TransferStrategyError.submissionFailed(error.error)
        }
    }
}
