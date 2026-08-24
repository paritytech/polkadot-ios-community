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
    private let durability: any DurabilityServicing
    private let originFactory: OriginCreating
    private let blockInfoProvider: any BlockInfoProviding
    private let currentDate: Date
    private let logger: SDKLoggerProtocol?

    init(
        readyCoins: [Coin],
        perGroupCoins: [RecyclerGroupCoins],
        voucherKeyFactory: any VoucherKeyDeriving,
        recyclerLoader: RecyclerReadinessLoading,
        coinKeyFactory: any CoinKeyDeriving,
        durability: any DurabilityServicing,
        originFactory: OriginCreating,
        blockInfoProvider: any BlockInfoProviding,
        currentDate: Date,
        logger: SDKLoggerProtocol?
    ) {
        self.readyCoins = readyCoins
        self.perGroupCoins = perGroupCoins
        self.voucherKeyFactory = voucherKeyFactory
        self.coinKeyFactory = coinKeyFactory
        self.recyclerLoader = recyclerLoader
        self.durability = durability
        self.originFactory = originFactory
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

        var collectedErrors = try await submitGroups(context: context, allVouchers: allVouchers)

        // Process ready coins regardless of extrinsic errors — they require no on-chain submission.
        if !readyCoins.isEmpty {
            do {
                try await context.handOff(coins: readyCoins)
            } catch {
                logger?.error("Failed to record ready coins locally: \(error)")
                collectedErrors.append(error)
            }
        }

        await context.settle()

        guard collectedErrors.isEmpty else {
            throw TransferStrategyError.multiple(collectedErrors)
        }
    }
}

// MARK: - Private Helpers

private extension UnloadIntoCoinsStrategy {
    /// Registers one entry per recycler group before any network round-trip, so no reconcile
    /// can observe an input this transfer reserved but no entry explains.
    ///
    /// All N commit before any bytes go on the wire. Each entry still commits before its own
    /// extrinsic is broadcast; a crash in between leaves registered-but-unsubmitted entries
    /// that reach FAILURE at mortality and return their inputs.
    func registerGroups() async throws -> [TransactionId] {
        var registered: [TransactionId] = []

        do {
            for groupCoins in perGroupCoins {
                let id = try await durability.register(
                    inputs: groupCoins.vouchers.map { .recyclerVoucher($0.derivationIndex) },
                    outputs: (groupCoins.recipientCoins + groupCoins.changeCoins)
                        .map { .coin($0.derivationIndex) }
                )
                registered.append(id)
            }
        } catch {
            registered.forEach { durability.abandon($0) }
            throw error
        }

        return registered
    }

    func submitGroups(context: TransferContext, allVouchers: [Voucher]) async throws -> [Error] {
        let entryIds = try await registerGroups()

        do {
            // Reservation follows registration: the entry set already explains every input, so a
            // reconcile landing during the network preparation below cannot demote it.
            try await context.reserve(coins: readyCoins, vouchers: allVouchers)

            // Fetch finalized block hash upfront to ensure both operations query the same state
            let blockHash = try await blockInfoProvider.fetchCurrentHash()

            // Create all origins upfront — each group needs a distinct unload token.
            let origins = try await originFactory.createAsUnloadTokenOrigins(
                voucherGroups: perGroupCoins.map(\.vouchers),
                currentDate: currentDate,
                blockHash: blockHash
            )

            // zip truncates to the shortest sequence, so a short origins array would silently drop
            // groups whose entries are already registered — leaving them owned, unsubmitted, and
            // invisible to every future recovery pass.
            guard origins.count == perGroupCoins.count else {
                assertionFailure("Origin for recycler group is missing")
                throw TransferStrategyError.invalidRecyclerRevision
            }

            logger?.info(
                "Submitting \(perGroupCoins.count) unload extrinsics for \(allVouchers.count) vouchers"
            )

            let keys = perGroupCoins.map(\.recyclerKey)
            let revisions = try await recyclerLoader.fetchRevisions(for: keys, blockHash: blockHash)

            guard keys.count == revisions.count else {
                assertionFailure("Revision for recyclerKey is missing")
                throw TransferStrategyError.invalidRecyclerRevision
            }

            // Insert every group's output coins in one write before launching tasks
            try await context.insertOutputs(
                coins: perGroupCoins.flatMap { $0.recipientCoins + $0.changeCoins }
            )

            // Non-throwing task group — a failure in one group must not discard already-committed
            // results from other groups. Each group maps to exactly one RecyclerKey.
            typealias GroupResult = Result<
                (spentVouchers: [Voucher], changeCoins: [Coin], destinationCoins: [Coin]),
                Error
            >

            let allResults: [GroupResult] = await withTaskGroup(
                of: GroupResult.self
            ) { [durability, voucherKeyFactory, coinKeyFactory, logger] taskGroup in
                for ((groupCoins, origin), entryId) in zip(zip(perGroupCoins, origins), entryIds) {
                    let revision = revisions[groupCoins.recyclerKey]! // validated above

                    taskGroup.addTask {
                        do {
                            let value = try await processItem(
                                groupCoins: groupCoins,
                                origin: origin,
                                revision: revision,
                                entryId: entryId,
                                voucherKeyFactory: voucherKeyFactory,
                                coinKeyFactory: coinKeyFactory,
                                durability: durability,
                                logger: logger
                            )
                            return .success(value)
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
            var collectedErrors: [Error] = []
            for groupResult in allResults {
                switch groupResult {
                case let .success(group):
                    do {
                        let exponent = group.spentVouchers.first.map { "\($0.exponent)" } ?? "n/a"
                        logger?.info(
                            "Unload complete successfully: "
                                + "\(group.spentVouchers.count) vouchers, exponent \(exponent)"
                        )
                        try await context.handOff(coins: group.destinationCoins)
                    } catch {
                        logger?.error("Failed to record unload locally: \(error)")
                        collectedErrors.append(error)
                    }
                case let .failure(error):
                    logger?.error("Unload task failed: \(error)")
                    collectedErrors.append(error)
                }
            }

            return collectedErrors
        } catch {
            entryIds.forEach { durability.abandon($0) }
            throw error
        }
    }

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
        entryId: TransactionId,
        voucherKeyFactory: any VoucherKeyDeriving,
        coinKeyFactory: any CoinKeyDeriving,
        durability: any DurabilityServicing,
        logger: SDKLoggerProtocol?
    ) async throws -> (spentVouchers: [Voucher], changeCoins: [Coin], destinationCoins: [Coin]) {
        let key = groupCoins.recyclerKey

        let call: CoinagePallet.Calls.UnloadRecyclerIntoCoins
        do {
            call = try buildCall(
                for: groupCoins,
                revision: revision,
                voucherKeyFactory: voucherKeyFactory,
                coinKeyFactory: coinKeyFactory
            )
        } catch {
            // Nothing was submitted for this entry, so ownership must go back or the pass
            // skips it forever.
            durability.abandon(entryId)
            throw error
        }

        let result = try await durability.submitRegistered(
            entryId: entryId,
            builder: { try $0.adding(call: call.callAsFunction()) },
            origin: origin
        )

        switch result.submission.status {
        case .success:
            logger?.debug("Unload extrinsic succeeded for key \(key)")
            return (groupCoins.vouchers, groupCoins.changeCoins, groupCoins.recipientCoins)
        case let .failure(error):
            logger?.error("Unload extrinsic failed for key \(key): \(error.error)")
            throw TransferStrategyError.submissionFailed(error.error)
        }
    }
}
