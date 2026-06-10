import Foundation
import BigInt
import SubstrateSdk
import SDKLogger

/// Protocol for a coin unload to complete transfer.
protocol TransferSenderServicing: Actor {
    /// Preview the coin selection strategy without executing.
    ///
    /// - Parameters:
    ///   - amount: Amount to preview
    ///   - availableCoins: Coins available for selection
    ///   - availableVouchers: Vouchers available for selection
    ///   - currentDate: Current date for voucher readiness checking
    ///   - breakdownContext: Context for denomination breakdown
    /// - Returns: The coin selection result
    /// - Throws: CoinSelectionError on failure
    func previewStrategy(
        amount: BigUInt,
        availableCoins: [Coin],
        availableVouchers: [Voucher],
        breakdownContext: DenominationBreakdownContext
    ) async throws -> CoinSelectionResult

    /// Execute a transfer from a pre-computed coin selection result, skipping coin selection.
    func execute(
        result: CoinSelectionResult,
        currentDate: Date,
        breakdownContext: DenominationBreakdownContext,
        context: TransferContext
    ) async throws -> TransferMemo
}

extension TransferSenderServicing {
    func execute(
        result: CoinSelectionResult,
        breakdownContext: DenominationBreakdownContext,
        context: TransferContext
    ) async throws -> TransferMemo {
        try await execute(result: result, currentDate: .now, breakdownContext: breakdownContext, context: context)
    }
}

/// Orchestrates the complete coin transfer sender flow.
///
/// Flow:
/// 1. Select coins via CoinSelector → CoinSelectionResult
/// 2. Create plan via TransferPlanFactory → TransferPlan (strategy + memo entries)
/// 3. Execute strategy (persists state via context)
/// 4. Build memo from planned entries via MemoBuilder
/// 5. Return memo for recipient
actor TransferSenderService {
    private let coinSelector: CoinSelecting
    private let planFactory: TransferPlanCreating
    private let memoBuilder: MemoBuilding
    private let recyclerLoader: RecyclerReadinessLoading
    private let logger: SDKLoggerProtocol?

    private var cachedMaxVouchers: Int?

    init(
        coinSelector: CoinSelecting,
        planFactory: TransferPlanCreating,
        memoBuilder: MemoBuilding,
        recyclerLoader: RecyclerReadinessLoading,
        logger: SDKLoggerProtocol?
    ) {
        self.coinSelector = coinSelector
        self.planFactory = planFactory
        self.memoBuilder = memoBuilder
        self.recyclerLoader = recyclerLoader
        self.logger = logger
    }
}

private extension TransferSenderService {
    func maxVouchersPerGroup() async throws -> Int {
        if let cached = cachedMaxVouchers {
            return cached
        }
        let value = try await max(Int(recyclerLoader.maxConsolidation()), 1)
        cachedMaxVouchers = value
        return value
    }
}

extension TransferSenderService: TransferSenderServicing {
    func execute(
        result: CoinSelectionResult,
        currentDate: Date,
        breakdownContext: DenominationBreakdownContext,
        context: TransferContext
    ) async throws -> TransferMemo {
        let plan: TransferPlan
        do {
            plan = try await planFactory.createPlan(for: result, currentDate: currentDate)
        } catch {
            logger?.error("Plan creation failed: \(error)")
            throw TransferSenderServiceError.planCreationFailed(error)
        }

        let memo: TransferMemo
        do {
            memo = try memoBuilder.buildMemo(from: plan.plannedMemoEntries, breakdownContext: breakdownContext)
        } catch {
            logger?.error("Memo building failed: \(error)")
            throw TransferSenderServiceError.memoBuildingFailed(error)
        }

        try await context.reserve(coins: result.inputCoins, vouchers: result.inputVouchers)

        Task { [strategy = plan.strategy, logger] in
            do {
                try await strategy.run(context: context)
                logger?.debug("Strategy execution completed")
            } catch {
                logger?.error("Strategy execution failed: \(error)")
                await context.revert()
            }
        }

        return memo
    }

    func previewStrategy(
        amount: BigUInt,
        availableCoins: [Coin],
        availableVouchers: [Voucher],
        breakdownContext: DenominationBreakdownContext
    ) async throws -> CoinSelectionResult {
        let maxVouchers = try await maxVouchersPerGroup()
        let input = SelectCoinsInput(
            amount: amount,
            coins: availableCoins,
            vouchers: availableVouchers,
            breakdownContext: breakdownContext,
            maxVouchersPerGroup: maxVouchers
        )

        return try await coinSelector.selectCoins(input)
    }
}
