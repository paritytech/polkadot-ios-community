import BigInt
import Foundation
import Foundation_iOS
import SubstrateSdk
import PolkadotUI
import Coinage
import ChainRegistry
import Products

@MainActor
final class AssetDetailsPresenter {
    weak var view: AssetDetailsViewProtocol?

    let wireframe: AssetDetailsWireframeProtocol
    let interactor: AssetDetailsInteractorInputProtocol?

    let viewModelFactory: WalletCardViewModelFactoryProtocol
    private let balanceFormatterFactory: AssetBalanceFormatterFactoryProtocol
    private var balanceFormatter: LocalizableDecimalFormatting?
    private var priceFormatter: LocalizableDecimalFormatting?
    private lazy var fundingConfiguration: AssetFundingStatusView.Configuration =
        .fundingDigitalDollarConfiguration()

    private let chainAsset: ChainAsset
    private var balance: Decimal = 0
    private var lockedAmount: Decimal = 0
    private var coins: [TrackedCoin] = []
    private var vouchers: [TrackedVoucher] = []
    #if TESTNET_FEATURE
        /// Non-nil while the debug switch is on; shadows `coins`/`vouchers` for display only.
        private var fixtureCoinage: (coins: [TrackedCoin], vouchers: [TrackedVoucher])?
        /// Loaded from chain state; needed to price individual holdings.
        private var denominationContext: DenominationBreakdownContext?

        /// Fixtures carry their own pricing so test data renders without the chain.
        private var activeDenominationContext: DenominationBreakdownContext? {
            fixtureCoinage != nil ? CoinageFixtures.denominationContext : denominationContext
        }

        /// `TrackedCoin.isBalanceCounted` is the domain's single inclusion rule, so the list
        /// shows exactly what the balance counts — for fixtures too, since they are tracked.
        private var displayedCoins: [Coin] {
            (fixtureCoinage?.coins ?? coins).filter(\.isBalanceCounted).map(\.coin)
        }

        private var displayedVouchers: [Voucher] {
            (fixtureCoinage?.vouchers ?? vouchers).filter(\.isBalanceCounted).map(\.voucher)
        }
    #endif
    private var price: PriceData?
    let logger: LoggerProtocol

    init(
        interactor: AssetDetailsInteractorInputProtocol,
        wireframe: AssetDetailsWireframeProtocol,
        viewModelFactory: WalletCardViewModelFactoryProtocol,
        logger: LoggerProtocol,
        chainAsset: ChainAsset,
        balanceFormatterFactory: AssetBalanceFormatterFactoryProtocol = AssetBalanceFormatterFactory()
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.viewModelFactory = viewModelFactory
        self.logger = logger
        self.chainAsset = chainAsset
        self.balanceFormatterFactory = balanceFormatterFactory
    }

    private func provideAssets() {
        let viewModels = [viewModelFactory.createAssetViewModel(from: chainAsset)]
        view?.didSetCards(viewModels: viewModels)
    }

    private func provideAssetBalance() {
        let balanceViewModelFactory = PrimitiveBalanceViewModelFactory(
            targetAssetInfo: chainAsset.asset.digitalDollarDisplayInfo.withoutSymbol,
            formatterFactory: balanceFormatterFactory
        )

        let balanceViewModel = balanceViewModelFactory.balanceFromPrice(
            balance,
            priceData: price
        )
        .value(for: .current)

        view?.didReceiveData(viewModel: .token(balanceViewModel), index: 0)

        guard lockedAmount > 0 else {
            view?.didReceive(lockedAmount: nil)
            return
        }

        let lockedViewModel = balanceViewModelFactory.balanceFromPrice(
            lockedAmount,
            priceData: price
        )
        .value(for: .current)

        view?.didReceive(lockedAmount: lockedViewModel)
    }
}

extension AssetDetailsPresenter: AssetDetailsPresenterProtocol {
    func onBackupSync() {
        interactor?.triggerSync()
    }

    func onBackupCancel() {
        wireframe.showCancelBackupConfirmation(from: view) { [weak self] in
            self?.interactor?.cancelBackupNotification()
        }
    }

    func onBackupWhyUpdate() {
        wireframe.showWhyBackupUpdate(from: view)
    }

    func setup() {
        provideAssets()
        provideAssetBalance()
        interactor?.setup()
    }

    func onSendMoney() {
        wireframe.showTransfer(from: view, chainAsset: chainAsset)
    }

    func onAddMoney() {
        wireframe.showAddTokens(from: view)
    }

    func onFundingCompletedAction() {
        interactor?.removeCompletedFiatOnrampTransactions()
    }

    func onFundingFailedAction() {
        interactor?.removeFailedFiatOnrampTransactions()
    }

    func onTopUp() {
        view?.didReceive(topUpLoading: true)

        interactor?.openTopUpProduct()
    }

    #if TESTNET_FEATURE
        func onTestnetTopUp() {
            view?.didReceive(testnetTopUpLoading: true)

            interactor?.topUp()
        }

        func onToggleFixtureCoinage() {
            // Regenerated on every enable so voucher timestamps stay relative to "now".
            fixtureCoinage = fixtureCoinage == nil ? CoinageFixtures.make() : nil
            view?.didReceive(usesFixtureCoinage: fixtureCoinage != nil)
            provideCoinageBreakdown()
        }

        func onMakeAllVouchersReady() {
            interactor?.makeAllVouchersReady()
        }
    #endif
}

extension AssetDetailsPresenter: AssetDetailsInteractorOutputProtocol {
    func didResolveTopUpProduct(_ result: Result<ProductPage, Error>) {
        view?.didReceive(topUpLoading: false)

        switch result {
        case let .success(page):
            wireframe.showProduct(page: page)
        case let .failure(error):
            wireframe.present(error: error, from: view)
        }
    }

    #if TESTNET_FEATURE
        func didCompleteTopUp(_ result: Result<Void, Error>) {
            view?.didReceive(testnetTopUpLoading: false)

            guard case let .failure(error) = result else {
                return
            }

            wireframe.present(error: error, from: view)
        }

        func didReceive(denominationContext: DenominationBreakdownContext) {
            self.denominationContext = denominationContext
            provideCoinageBreakdown()
        }

        func didReceive(coins: [TrackedCoin], vouchers: [TrackedVoucher]) {
            self.coins = coins
            self.vouchers = vouchers
            provideCoinageBreakdown()
        }
    #endif

    func didReceive(fiatOnrampStatuses: Set<FiatOnrampTransactionStatusPayload>) {
        provideFundingStates(from: fiatOnrampStatuses)
    }

    func didReceive(balance: Decimal) {
        self.balance = balance
        provideAssetBalance()
        #if TESTNET_FEATURE
            provideCoinageBreakdown()
        #endif
    }

    func didReceive(lockedAmount: Decimal) {
        self.lockedAmount = lockedAmount
        provideAssetBalance()
        #if TESTNET_FEATURE
            provideCoinageBreakdown()
        #endif
    }

    func didReceive(price: PriceData?) {
        self.price = price
        provideAssetBalance()
    }

    func didFail(recovery error: Error) {
        wireframe.present(error: error, from: view)
    }

    func didReceive(isRecoveryInProgress: Bool) {
        view?.didReceive(isRecoveryInProgress: isRecoveryInProgress)
    }

    func didCompleteRecovery() {
        view?.didShowBackupNotification()
    }

    func didClearBackupNotification() {
        view?.didHideBackupNotification()
    }
}

private extension AssetDetailsPresenter {
    func provideFundingStates(from statuses: Set<FiatOnrampTransactionStatusPayload>) {
        let sortedStatuses = statuses.sorted { lhs, rhs in
            lhs.id.value < rhs.id.value
        }

        let states: [AssetFundingStatusView.FundingState] = sortedStatuses.map { status in
            switch status.status {
            case .funding:
                .init(id: status.id.value, status: .waiting)
            case let .inProgress(remainedTime, inAmount, outAmount):
                .init(
                    id: status.id.value,
                    status: .inProgress(
                        totalSeconds: Int(ceil(remainedTime)),
                        amountIn: formatAmount(inAmount),
                        amountOut: formatUsdAmount(outAmount)
                    )
                )
            case let .completed(inAmount, outAmount):
                .init(
                    id: status.id.value,
                    status: .completed(
                        amountIn: formatAmount(inAmount),
                        amountOut: formatUsdAmount(outAmount)
                    )
                )
            case .failed:
                .init(id: status.id.value, status: .failed)
            }
        }

        view?.didReceive(fundingStates: states)
    }

    func formatAmount(_ amount: Balance) -> String {
        let formatter = getBalanceFormatter()
        let decimalAmount = amount.decimal(assetInfo: chainAsset.assetDisplayInfo)
        return formatter.stringFromDecimal(decimalAmount) ?? ""
    }

    func getBalanceFormatter() -> LocalizableDecimalFormatting {
        if let balanceFormatter {
            return balanceFormatter
        }

        let formatter = balanceFormatterFactory
            .createTokenFormatter(for: chainAsset.assetDisplayInfo)
            .value(for: .current)

        balanceFormatter = formatter

        return formatter
    }

    func getPriceFormatter() -> LocalizableDecimalFormatting {
        if let priceFormatter {
            return priceFormatter
        }

        let formatter = balanceFormatterFactory
            .createAssetPriceFormatter(for: .usd)
            .value(for: .current)

        priceFormatter = formatter

        return formatter
    }

    func formatUsdAmount(_ amount: Balance) -> String {
        let formatter = getPriceFormatter()
        let decimalAmount = amount.decimal(assetInfo: chainAsset.assetDisplayInfo)
        return formatter.stringFromDecimal(decimalAmount) ?? ""
    }
}

#if TESTNET_FEATURE
    private extension AssetDetailsPresenter {
        func provideCoinageBreakdown() {
            func formatted(from decimal: Decimal, includeSymbol: Bool = true) -> String {
                let assetInfo = chainAsset.asset.digitalDollarDisplayInfo
                let balanceViewModelFactory = PrimitiveBalanceViewModelFactory(
                    targetAssetInfo: includeSymbol ? assetInfo : assetInfo.withoutSymbol,
                    formatterFactory: balanceFormatterFactory
                )
                return balanceViewModelFactory.balanceFromPrice(
                    decimal,
                    priceData: price
                )
                .value(for: .current)
                .amount
            }

            let context = activeDenominationContext

            // Pulled out of the map closures below: inlining it defeats the type checker.
            func amount(forExponent exponent: Int16) -> String? {
                guard let context else { return nil }

                return formatted(from: context.amount(forExponent: exponent), includeSymbol: false)
            }

            // Value descending, then best fungibility first. Value is `unit * 2^exponent`,
            // so ordering by exponent is exactly ordering by value.
            let coinDetails = displayedCoins
                .sorted { lhs, rhs in
                    lhs.exponent == rhs.exponent
                        ? (lhs.fungibilityScore ?? 0) > (rhs.fungibilityScore ?? 0)
                        : lhs.exponent > rhs.exponent
                }
                .map { coin in
                    CoinageHoldingViewModel(
                        id: coin.identifier,
                        amount: amount(forExponent: coin.exponent),
                        fungibility: Self.fungibilityModel(for: coin)
                    )
                }

            let voucherDetails = displayedVouchers
                .sorted { lhs, rhs in
                    lhs.exponent == rhs.exponent
                        ? (lhs.fungibilityScore ?? 0) > (rhs.fungibilityScore ?? 0)
                        : lhs.exponent > rhs.exponent
                }
                .map { voucher in
                    CoinageHoldingViewModel(
                        id: voucher.identifier,
                        amount: amount(forExponent: voucher.exponent),
                        fungibility: .voucher(score: voucher.fungibilityScore ?? 0)
                    )
                }

            let amounts = fixtureAmounts() ?? (
                total: balance,
                spendable: balance - lockedAmount,
                pending: lockedAmount
            )

            let breakdown = CoinageBalanceBreakdownViewModel(
                totalBalance: formatted(from: amounts.total),
                spendableBalance: formatted(from: amounts.spendable),
                pendingBalance: formatted(from: amounts.pending),
                composition: context.map {
                    Self.composition(coins: displayedCoins, vouchers: displayedVouchers, context: $0)
                } ?? .empty,
                coinDetails: coinDetails,
                voucherDetails: voucherDetails
            )
            view?.didReceive(coinageBreakdown: breakdown)
        }

        /// Totals the fixture holdings. Fixtures are all unclaimed and on chain, so there is
        /// nothing pending — the interesting fixture signal is the per-holding depiction and the
        /// composition bar, not the lifecycle split.
        func fixtureAmounts() -> (total: Decimal, spendable: Decimal, pending: Decimal)? {
            guard fixtureCoinage != nil else { return nil }

            let context = CoinageFixtures.denominationContext
            let exponents = displayedCoins.map(\.exponent) + displayedVouchers.map(\.exponent)
            let total = exponents.reduce(Decimal.zero) { $0 + context.amount(forExponent: $1) }

            return (total: total, spendable: total, pending: 0)
        }

        /// Value-weighted split of the holdings into private / loading / public.
        ///
        /// A holding counts as private once it reaches the same high band the per-row bars
        /// paint green — coins *and* vouchers alike. Anything short of that is public if it is
        /// a coin, or still loading if it is a voucher, since a voucher can yet improve as its
        /// recycler fills. Spent coins are not held and are excluded.
        static func composition(
            coins: [Coin],
            vouchers: [Voucher],
            context: DenominationBreakdownContext
        ) -> PrivacyCompositionBar.Model {
            var privatePlanks = BigUInt(0)
            var publicPlanks = BigUInt(0)
            var loadingPlanks = BigUInt(0)

            for coin in coins {
                let value = context.valueInPlanks(for: coin.exponent)
                if FungibilityBand(score: coin.fungibilityScore ?? 0) == .high {
                    privatePlanks += value
                } else {
                    publicPlanks += value
                }
            }

            for voucher in vouchers {
                let value = context.valueInPlanks(for: voucher.exponent)
                if FungibilityBand(score: voucher.fungibilityScore ?? 0) == .high {
                    privatePlanks += value
                } else {
                    loadingPlanks += value
                }
            }

            let total = privatePlanks + publicPlanks + loadingPlanks

            guard total > 0 else { return .empty }

            // Scaled integer division keeps this exact for plank counts far beyond Double.
            func share(_ part: BigUInt) -> Double {
                let scale = BigUInt(1_000_000)
                return Double(part * scale / total) / Double(scale)
            }

            return PrivacyCompositionBar.Model(
                privateShare: share(privatePlanks),
                loadingShare: share(loadingPlanks),
                publicShare: share(publicPlanks)
            )
        }

        /// Maps a coin's provenance onto the depiction.
        ///
        /// A split hop fans out from the node it originated at — the node *before* it — so
        /// hop `i` being a split marks node `i-1`, where node `-1` is the recycler square.
        /// The final dot therefore never fans out: it is "here, now".
        static func fungibilityModel(for coin: Coin) -> FungibilityBarView.Model {
            let branches = coin.hops.map { hop in
                switch hop {
                case .transfer: 0
                case let .split(fanout): FungibilityBarView.Model.branches(forFanout: fanout)
                }
            }

            // An unknown recycler fungibility scores as zero: a privacy indicator should not
            // claim a holding is private when its provenance is unknown.
            return FungibilityBarView.Model(
                score: coin.fungibilityScore ?? 0,
                recyclerScore: coin.recyclerFungibility ?? 0,
                squareBranches: branches.first ?? 0,
                hopBranches: branches.indices.map { index in
                    let next = index + 1
                    return next < branches.count ? branches[next] : 0
                }
            )
        }
    }
#endif
