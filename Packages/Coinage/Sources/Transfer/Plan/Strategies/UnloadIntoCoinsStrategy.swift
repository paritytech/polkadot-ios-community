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
    private let perGroupAllocations: [RecyclerGroupAllocation]
    private let minter: any CoinMinting
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
        perGroupAllocations: [RecyclerGroupAllocation],
        minter: any CoinMinting,
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
        self.perGroupAllocations = perGroupAllocations
        self.minter = minter
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
    func prepare() async throws -> PreparedStrategy {
        guard !perGroupAllocations.isEmpty else {
            throw TransferStrategyError.emptyVouchers
        }

        let allVouchers = perGroupAllocations.flatMap(\.vouchers)

        guard !allVouchers.contains(where: { $0.recycler == nil }) else {
            throw TransferStrategyError.missingRecyclerInfo
        }

        // Mint each group's outputs.
        var realizedGroups: [RecyclerGroupCoins] = []
        for allocation in perGroupAllocations {
            let recipientCoins = try await minter
                .mintCoins(allocation.recipientDenominations.map(\.exponent))
            let changeCoins = try await minter
                .mintCoins(allocation.changeDenominations.map(\.exponent))
            realizedGroups.append(RecyclerGroupCoins(
                recyclerKey: allocation.recyclerKey,
                vouchers: allocation.vouchers,
                recipientCoins: recipientCoins,
                changeCoins: changeCoins
            ))
        }

        // Fetch on-chain state and build every group's request before submitting any, so a build
        // failure aborts before a single extrinsic is broadcast.
        let requests = try await buildRequests(for: realizedGroups)

        // One fire-and-forget submit per group: each registers (claiming its vouchers) and
        // broadcasts, returning once committed. The projection writes below follow.
        logger?.info("Submitting \(requests.count) unload extrinsics for \(allVouchers.count) vouchers")
        for request in requests {
            try await durability.submit(
                inputs: request.inputs,
                outputs: request.outputs,
                builder: request.builder,
                origin: request.origin
            )
        }

        // Ready coins need no submission; every group's recipient coins leave to the peer. Change
        // coins stay ours. All pre-committed before the memo can leave.
        let handedOff = readyCoins + realizedGroups.flatMap(\.recipientCoins)
        let handoffCommit = try await durability
            .preCommitHandoff(handedOff.map { .coin($0.derivationIndex) })

        var memoEntries = readyCoins.map {
            PlannedMemoEntry(
                coinDerivationIndex: $0.derivationIndex,
                valueExponent: $0.exponent,
                source: .existingCoin(age: Int32($0.age ?? 0))
            )
        }
        for group in realizedGroups {
            memoEntries += group.recipientCoins.map {
                PlannedMemoEntry(
                    coinDerivationIndex: $0.derivationIndex, valueExponent: $0.exponent, source: .fromUnload
                )
            }
        }

        return PreparedStrategy(memoEntries: memoEntries, handoffCommit: handoffCommit)
    }
}

// MARK: - Private Helpers

private extension UnloadIntoCoinsStrategy {
    struct GroupRequest {
        let inputs: [DurabilityInput]
        let outputs: [OwnAsset]
        let builder: ExtrinsicBuilderClosure
        let origin: any ExtrinsicOriginDefining
    }

    /// Fetches on-chain state (finalized block hash, unload-token origins, recycler revisions) and
    /// builds one request per group. Nothing is submitted here, so a build failure aborts the whole
    /// transfer before any extrinsic goes on the wire.
    func buildRequests(for realizedGroups: [RecyclerGroupCoins]) async throws -> [GroupRequest] {
        // Fetch finalized block hash upfront to ensure both operations query the same state.
        let blockHash = try await blockInfoProvider.fetchCurrentHash()

        // Create all origins upfront — each group needs a distinct unload token.
        let origins = try await originFactory.createAsUnloadTokenOrigins(
            voucherGroups: realizedGroups.map(\.vouchers),
            currentDate: currentDate,
            blockHash: blockHash
        )
        guard origins.count == realizedGroups.count else {
            assertionFailure("Origin for recycler group is missing")
            throw TransferStrategyError.invalidRecyclerRevision
        }

        let keys = realizedGroups.map(\.recyclerKey)
        let revisions = try await recyclerLoader.fetchRevisions(for: keys, blockHash: blockHash)
        guard keys.count == revisions.count else {
            assertionFailure("Revision for recyclerKey is missing")
            throw TransferStrategyError.invalidRecyclerRevision
        }

        return try zip(realizedGroups, origins).map { groupCoins, origin in
            let revision = revisions[groupCoins.recyclerKey]! // validated above
            let call = try buildCall(for: groupCoins, revision: revision)
            return GroupRequest(
                inputs: groupCoins.vouchers.map { .recyclerVoucher($0.derivationIndex) },
                outputs: (groupCoins.recipientCoins + groupCoins.changeCoins)
                    .map { .coin($0.derivationIndex) },
                builder: { try $0.adding(call: call.callAsFunction()) },
                origin: origin
            )
        }
    }

    func buildCall(
        for groupCoins: RecyclerGroupCoins,
        revision: UInt32
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
}
