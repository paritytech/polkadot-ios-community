import Foundation
import ExtrinsicService
import KeyDerivation
import SubstrateSdk
import SDKLogger
import SubstrateOperation

/// Factory interface for creating a `TransferPlan` (the strategy to execute) from a selection result.
protocol TransferPlanCreating {
    /// Builds the execution strategy for a coin selection result. Allocation, registration, and memo
    /// building all happen later, inside the strategy's `prepare`.
    func createPlan(
        for selectionResult: CoinSelectionResult,
        currentDate: Date
    ) async throws -> TransferPlan
}

final class TransferPlanFactory {
    private let transactionFactory: any CoinageTransactionFactoryProtocol
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let coinKeyFactory: any CoinKeyDeriving
    private let durability: any DurabilityServicing
    private let originFactory: OriginCreating
    private let recyclerLoader: RecyclerReadinessLoading
    private let blockInfoProvider: any BlockInfoProviding
    private let logger: SDKLoggerProtocol?

    init(
        transactionFactory: any CoinageTransactionFactoryProtocol,
        voucherKeyFactory: any VoucherKeyDeriving,
        coinKeyFactory: any CoinKeyDeriving,
        durability: any DurabilityServicing,
        originFactory: OriginCreating,
        recyclerLoader: RecyclerReadinessLoading,
        blockInfoProvider: any BlockInfoProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.transactionFactory = transactionFactory
        self.voucherKeyFactory = voucherKeyFactory
        self.coinKeyFactory = coinKeyFactory
        self.durability = durability
        self.originFactory = originFactory
        self.recyclerLoader = recyclerLoader
        self.blockInfoProvider = blockInfoProvider
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
            TransferPlan(strategy: ExactMatchStrategy(coins: coins, durability: durability))

        case let .split(wholeCoins, overflowCoin, targetDenominations, changeDenominations):
            TransferPlan(strategy: SplitCoinStrategy(
                wholeCoins: wholeCoins,
                overflowCoin: overflowCoin,
                targetDenominations: targetDenominations,
                changeDenominations: changeDenominations,
                transactionFactory: transactionFactory,
                coinKeyFactory: coinKeyFactory,
                durability: durability,
                originFactory: originFactory,
                logger: logger
            ))

        case let .unloadIntoCoins(coins, perGroupAllocations):
            TransferPlan(strategy: UnloadIntoCoinsStrategy(
                readyCoins: coins,
                perGroupAllocations: perGroupAllocations,
                transactionFactory: transactionFactory,
                voucherKeyFactory: voucherKeyFactory,
                recyclerLoader: recyclerLoader,
                coinKeyFactory: coinKeyFactory,
                durability: durability,
                originFactory: originFactory,
                blockInfoProvider: blockInfoProvider,
                currentDate: currentDate,
                logger: logger
            ))
        }
    }
}
