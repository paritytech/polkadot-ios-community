import Foundation
import os
import SDKLogger

/// Buckets the tracked wallet through ``CoinageAssetSelector`` — the same verdict + usability rule
/// `CoinageService.selectableAssets` applies to transfers — so product payments never spend what
/// the privacy preset holds back.
final class RecyclingAwareSpendableAssetsProvider: SpendableAssetsProviding, @unchecked Sendable {
    private struct VerdictsSource {
        weak var reader: (any RecyclingVerdictsReading)?
    }

    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol
    private let settings: any CoinageRecyclingStrategyProviding
    private let strategyResolver: any RecyclingStrategyProviding
    private let ringCapacityProvider: any RingCapacityProviding
    private let preClassificator: any CoinageAssetsPreClassificating
    private let logger: SDKLoggerProtocol?
    private let verdictsSource = OSAllocatedUnfairLock(initialState: VerdictsSource())

    init(
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol,
        settings: any CoinageRecyclingStrategyProviding,
        strategyResolver: any RecyclingStrategyProviding,
        ringCapacityProvider: any RingCapacityProviding,
        preClassificator: any CoinageAssetsPreClassificating,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.coinService = coinService
        self.voucherService = voucherService
        self.settings = settings
        self.strategyResolver = strategyResolver
        self.ringCapacityProvider = ringCapacityProvider
        self.preClassificator = preClassificator
        self.logger = logger
    }

    func setVerdictsReader(_ reader: any RecyclingVerdictsReading) {
        verdictsSource.withLock { $0.reader = reader }
    }

    func spendableAssets(scope: SpendScope) async throws -> SpendableAssets? {
        guard let reader = verdictsSource.withLock({ $0.reader }),
              let verdicts = await reader.currentRecyclingVerdicts()
        else {
            return nil
        }

        let coins = try await coinService.fetchAllTrackedCoins()
        let vouchers = try await voucherService.fetchAllTracked()
        let strategy = strategyResolver.voucherStrategy(for: settings.strategy)
        let usability = await usabilityContext(for: vouchers)
        let selector = CoinageAssetSelector(preClassificator: preClassificator)

        let spendableCoins = selector.selectableCoins(
            coins,
            verdicts: verdicts,
            allowsConfirmedSpend: strategy.allowsConfirmedSpend(),
            scope: scope
        )
        let spendableVouchers = selector.selectableVouchers(
            vouchers,
            strategy: strategy,
            context: usability,
            scope: scope
        )

        let coinBuckets = preClassificator.preClassifyCoins(coins)
        let voucherBuckets = preClassificator.preClassifyVouchers(vouchers, strategy: strategy, context: usability)
        let spendableCoinIndices = Set(spendableCoins.map(\.coin.derivationIndex))
        let spendableVoucherIndices = Set(spendableVouchers.map(\.voucher.derivationIndex))

        let gainingCoins = coinBuckets.minted.filter {
            verdicts[$0.coin.derivationIndex] == .toRecycle && !spendableCoinIndices.contains($0.coin.derivationIndex)
        }
        let pendingCoins = coinBuckets.minting + coinBuckets.minted.filter {
            switch verdicts[$0.coin.derivationIndex] {
            case .mustRecycle,
                 .none: true
            case .allowUse,
                 .toRecycle: false
            }
        }
        let gainingVouchers = voucherBuckets.gainingPrivacy.filter {
            !spendableVoucherIndices.contains($0.voucher.derivationIndex)
        }

        return SpendableAssets(
            spendableCoins: spendableCoins.map(\.coin),
            spendableVouchers: spendableVouchers.map(\.voucher),
            gainingPrivacyCoins: gainingCoins.map(\.coin),
            gainingPrivacyVouchers: gainingVouchers.map(\.voucher),
            pendingCoins: pendingCoins.map(\.coin),
            pendingVouchers: voucherBuckets.minting.map(\.voucher)
        )
    }
}

private extension RecyclingAwareSpendableAssetsProvider {
    /// Chain-backed capacities when reachable; the memoised ones otherwise, so an RPC hiccup
    /// degrades to "not yet full" instead of failing the plan.
    func usabilityContext(for vouchers: [TrackedVoucher]) async -> VoucherUsabilityContext {
        let exponents = Set(vouchers.map(\.voucher.exponent))
        let capacities: [Int16: Int]

        do {
            capacities = try await ringCapacityProvider.capacities(for: exponents)
        } catch {
            logger?.warning("Ring capacities unavailable, planning on memoised values: \(error)")
            capacities = await ringCapacityProvider.peekCapacities(for: exponents)
        }

        return VoucherUsabilityContext(ringCapacities: capacities, now: Date())
    }
}
