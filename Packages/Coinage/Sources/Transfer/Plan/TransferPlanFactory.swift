import Foundation
import ExtrinsicService
import KeyDerivation
import SubstrateSdk
import SDKLogger
import SubstrateOperation

/// Factory interface for creating a complete TransferPlan from a CoinSelectionResult.
protocol TransferPlanCreating {
    /// Creates a complete transfer plan from a coin selection result.
    /// - Parameters:
    ///   - selectionResult: The coin selection result describing what to transfer
    /// recycler groups)
    ///   - currentDate: Current date for unload token period calculation
    /// - Returns: A complete `TransferPlan` with strategy, memo entries, and token requirements
    func createPlan(
        for selectionResult: CoinSelectionResult,
        currentDate: Date
    ) async throws -> TransferPlan
}

final class TransferPlanFactory {
    private let coinAllocator: CoinAllocating
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let coinKeyFactory: any CoinKeyDeriving
    private let coordinator: any ExtrinsicSubmissionCoordinating
    private let originFactory: OriginCreating
    private let recyclerLoader: RecyclerReadinessLoading
    private let walStore: any TransferWALStoring
    private let blockInfoProvider: any BlockInfoProviding
    // Not a real mortality, but the amount of blocks to wait
    // before reverting a transfer based on WAL
    private let mortality: BlockNumber
    private let logger: SDKLoggerProtocol?

    init(
        coinAllocator: CoinAllocating,
        voucherKeyFactory: any VoucherKeyDeriving,
        coinKeyFactory: any CoinKeyDeriving,
        coordinator: any ExtrinsicSubmissionCoordinating,
        originFactory: OriginCreating,
        recyclerLoader: RecyclerReadinessLoading,
        walStore: any TransferWALStoring,
        blockInfoProvider: any BlockInfoProviding,
        mortality: BlockNumber = CoinageConstants.walMortality,
        logger: SDKLoggerProtocol?
    ) {
        self.coinAllocator = coinAllocator
        self.voucherKeyFactory = voucherKeyFactory
        self.coinKeyFactory = coinKeyFactory
        self.coordinator = coordinator
        self.originFactory = originFactory
        self.recyclerLoader = recyclerLoader
        self.walStore = walStore
        self.blockInfoProvider = blockInfoProvider
        self.mortality = mortality
        self.logger = logger
    }
}

// MARK: - TransferPlanCreating

extension TransferPlanFactory: TransferPlanCreating {
    func createPlan(
        for selectionResult: CoinSelectionResult,
        currentDate: Date
    ) async throws -> TransferPlan {
        switch selectionResult {
        case let .exactMatch(coins):
            try createExactMatchPlan(coins: coins)

        case let .split(wholeCoins, overflowCoin, targetDenominations, changeDenominations):
            try await createSplitPlan(
                wholeCoins: wholeCoins,
                overflowCoin: overflowCoin,
                targetDenominations: targetDenominations,
                changeDenominations: changeDenominations
            )

        case let .unloadIntoCoins(coins, perGroupAllocations):
            try await createUnloadPlan(
                coins: coins,
                perGroupAllocations: perGroupAllocations,
                currentDate: currentDate
            )
        }
    }
}

// MARK: - Private

private extension TransferPlanFactory {
    func createExactMatchPlan(coins: [Coin]) throws -> TransferPlan {
        let memoEntries = coins.map { coin in
            PlannedMemoEntry(
                coinDerivationIndex: coin.derivationIndex,
                valueExponent: coin.exponent,
                source: .existingCoin(age: Int32(coin.age ?? 0))
            )
        }

        return TransferPlan(
            strategy: ExactMatchStrategy(coins: coins),
            plannedMemoEntries: memoEntries,
            claimTokensRequired: 0
        )
    }

    func createSplitPlan(
        wholeCoins: [Coin],
        overflowCoin: Coin,
        targetDenominations: [Denomination],
        changeDenominations: [Denomination]
    ) async throws -> TransferPlan {
        async let recipientCoinsTask = allocateCoins(for: targetDenominations)
        async let changeCoinsTask = allocateCoins(for: changeDenominations)

        let splitRecipientCoins = try await recipientCoinsTask
        let changeCoins = try await changeCoinsTask

        // Memo entries: whole coins (existing) + newly allocated coins from split
        var memoEntries = wholeCoins.map { coin in
            PlannedMemoEntry(
                coinDerivationIndex: coin.derivationIndex,
                valueExponent: coin.exponent,
                source: .existingCoin(age: Int32(coin.age ?? 0))
            )
        }

        memoEntries += splitRecipientCoins.map { coin in
            PlannedMemoEntry(
                coinDerivationIndex: coin.derivationIndex,
                valueExponent: coin.exponent,
                source: .fromSplit
            )
        }

        let strategy = SplitCoinStrategy(
            wholeCoins: wholeCoins,
            overflowCoin: overflowCoin,
            recipientCoins: splitRecipientCoins,
            changeCoins: changeCoins,
            coinKeyFactory: coinKeyFactory,
            coordinator: coordinator,
            originFactory: originFactory,
            walStore: walStore,
            mortality: mortality,
            logger: logger
        )

        return TransferPlan(
            strategy: strategy,
            plannedMemoEntries: memoEntries,
            claimTokensRequired: 0
        )
    }

    func createUnloadPlan(
        coins: [Coin],
        perGroupAllocations: [RecyclerGroupAllocation],
        currentDate: Date
    ) async throws -> TransferPlan {
        // Allocate coins per group to preserve the per-group structure
        let groupCoinsAllocations = try await allocateCoinsPerGroup(for: perGroupAllocations)

        // Memo entries: existing coins
        var memoEntries = coins.map { coin in
            PlannedMemoEntry(
                coinDerivationIndex: coin.derivationIndex,
                valueExponent: coin.exponent,
                source: .existingCoin(age: Int32(coin.age ?? 0))
            )
        }

        // Add memo entries for all recipient coins across all groups
        for groupCoins in groupCoinsAllocations {
            memoEntries += groupCoins.recipientCoins.map { coin in
                PlannedMemoEntry(
                    coinDerivationIndex: coin.derivationIndex,
                    valueExponent: coin.exponent,
                    source: .fromUnload
                )
            }
        }

        let strategy = UnloadIntoCoinsStrategy(
            readyCoins: coins,
            perGroupCoins: groupCoinsAllocations,
            voucherKeyFactory: voucherKeyFactory,
            recyclerLoader: recyclerLoader,
            coinKeyFactory: coinKeyFactory,
            coordinator: coordinator,
            originFactory: originFactory,
            walStore: walStore,
            mortality: mortality,
            blockInfoProvider: blockInfoProvider,
            currentDate: currentDate,
            logger: logger
        )

        return TransferPlan(
            strategy: strategy,
            plannedMemoEntries: memoEntries,
            claimTokensRequired: max(perGroupAllocations.count, 1)
        )
    }

    /// Allocates coins for each recycler group's denominations.
    func allocateCoinsPerGroup(
        for allocations: [RecyclerGroupAllocation]
    ) async throws -> [RecyclerGroupCoins] {
        try await withThrowingTaskGroup(of: (Int, RecyclerGroupCoins).self) { [weak self] group in
            guard let self else { return [] }

            for (index, allocation) in allocations.enumerated() {
                group.addTask {
                    async let recipientTask = self.allocateCoins(for: allocation.recipientDenominations)
                    async let changeTask = self.allocateCoins(for: allocation.changeDenominations)

                    return try await (index, RecyclerGroupCoins(
                        recyclerKey: allocation.recyclerKey,
                        vouchers: allocation.vouchers,
                        recipientCoins: recipientTask,
                        changeCoins: changeTask
                    ))
                }
            }

            var results: [(Int, RecyclerGroupCoins)] = []
            for try await result in group {
                results.append(result)
            }

            // Return in original order
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func allocateCoins(for denominations: [Denomination]) async throws -> [Coin] {
        try await withThrowingTaskGroup(of: Coin.self) { group in
            for denom in denominations {
                group.addTask { [coinAllocator] in
                    try await coinAllocator.allocate(exponent: denom.exponent)
                }
            }

            var results: [Coin] = []
            for try await coin in group {
                results.append(coin)
            }

            return results
        }
    }
}
