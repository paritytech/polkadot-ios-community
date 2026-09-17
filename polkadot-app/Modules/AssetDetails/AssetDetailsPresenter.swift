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
    /// Classified alongside the balance figures, so the rows and the bar always account for
    /// exactly the total shown above them.
    private var holdings: CoinageHoldings = .empty
    /// The domain's three buckets for the real holdings, totalled by the balance service.
    private var coinageAmounts: CoinageAmounts?
    /// Loaded from chain state; needed to price individual holdings.
    private var denominationContext: DenominationBreakdownContext?
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

    func didReceive(denominationContext: DenominationBreakdownContext) {
        self.denominationContext = denominationContext
        provideCoinageBreakdown()
    }

    func didReceive(coinageAmounts: CoinageAmounts, holdings: CoinageHoldings) {
        self.coinageAmounts = coinageAmounts
        self.holdings = holdings
        provideCoinageBreakdown()
    }

    #if TESTNET_FEATURE
        func didCompleteTopUp(_ result: Result<Void, Error>) {
            view?.didReceive(testnetTopUpLoading: false)

            guard case let .failure(error) = result else {
                return
            }

            wireframe.present(error: error, from: view)
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

        let context = denominationContext
        let holdings = holdings

        // Pulled out of the map closure below: inlining it defeats the type checker.
        func amount(forExponent exponent: Int16) -> String? {
            guard let context else { return nil }

            return formatted(from: context.amount(forExponent: exponent), includeSymbol: false)
        }

        /// Counts consecutive repeats rather than tallying the whole run, so the values stay in
        /// the order the ordering put them in.
        func folded(_ values: [String]) -> String {
            var parts: [(value: String, count: Int)] = []

            for value in values {
                if let last = parts.last, last.value == value {
                    parts[parts.count - 1].count += 1
                } else {
                    parts.append((value, 1))
                }
            }

            return parts
                .map { $0.count > 1 ? "\($0.value) ×\($0.count)" : $0.value }
                .joined(separator: "   ")
        }

        let groups = CoinageBreakdownFactory.group(CoinageBreakdownFactory.rows(from: holdings))
        let groupValues = groups.map { group in
            context.map { context in
                group.exponents.reduce(Decimal.zero) { $0 + context.amount(forExponent: $1) }
            } ?? 0
        }
        let peak = groupValues.max() ?? 0

        let rows = zip(groups, groupValues).map { group, value in
            CoinageHoldingGroupViewModel(
                id: group.id,
                status: group.status,
                amounts: folded(group.exponents.map { amount(forExponent: $0) ?? "—" }),
                count: group.exponents.count,
                share: peak > 0 ? NSDecimalNumber(decimal: value / peak).doubleValue : 0,
                total: context.map { _ in formatted(from: value, includeSymbol: false) }
            )
        }

        let amounts = coinageAmounts ?? .zero

        let bands = context.map { context in
            distribution(
                of: CoinageBreakdownFactory.group(CoinageBreakdownFactory.rows(from: holdings)),
                value: { context.amount(forExponent: $0) },
                formatted: { formatted(from: $0, includeSymbol: false) }
            )
        } ?? .empty

        let matrix = matrix(of: groups, amount: amount(forExponent:))

        let breakdown = CoinageBalanceBreakdownViewModel(
            totalBalance: formatted(from: amounts.total, includeSymbol: false),
            availableNowBalance: formatted(from: amounts.availableNow, includeSymbol: false),
            gainingPrivacyBalance: formatted(from: amounts.gainingPrivacy, includeSymbol: false),
            pendingBalance: formatted(from: amounts.pending, includeSymbol: false),
            symbol: chainAsset.asset.digitalDollarDisplayInfo.symbol,
            composition: context.map {
                CoinageBreakdownFactory.composition(of: holdings, context: $0)
            } ?? .empty,
            holdings: rows,
            distribution: bands,
            matrix: matrix
        )
        view?.didReceive(coinageBreakdown: breakdown)
    }

    /// Counts holdings per denomination and band. Denominations descend by value; every band is a
    /// column whether or not anything stands in it, so the columns line up across rows.
    func matrix(
        of groups: [CoinageBreakdownFactory.Group],
        amount: (Int16) -> String?
    ) -> CoinageHoldingMatrix {
        let ladder = [CoinageFungibilityDistribution.unknownBand]
            + (0 ... CoinageStatusMetrics.maximumBucket).reversed()

        var counts: [Int16: [Int: Int]] = [:]

        for group in groups {
            let band = CoinageBreakdownFactory.band(for: group.status)

            for exponent in group.exponents {
                counts[exponent, default: [:]][band, default: 0] += 1
            }
        }

        let rows = counts.keys.sorted(by: >).map { exponent in
            CoinageHoldingMatrix.Row(
                id: exponent,
                amount: amount(exponent) ?? "—",
                counts: ladder.map { counts[exponent]?[$0] ?? 0 }
            )
        }

        return CoinageHoldingMatrix(bands: ladder, rows: rows)
    }

    /// Totals every band on the ladder, empty ones included, and scales them against the fullest
    /// so the tallest band always reaches the top of the chart whatever the balance is.
    func distribution(
        of groups: [CoinageBreakdownFactory.Group],
        value: (Int16) -> Decimal,
        formatted: (Decimal) -> String
    ) -> CoinageFungibilityDistribution {
        var totals: [Int: Decimal] = [:]

        for group in groups {
            let band = CoinageBreakdownFactory.band(for: group.status)
            totals[band, default: 0] += group.exponents.reduce(Decimal.zero) { $0 + value($1) }
        }

        let ladder = [CoinageFungibilityDistribution.unknownBand]
            + (0 ... CoinageStatusMetrics.maximumBucket).reversed()
        let peak = totals.values.max() ?? 0

        return CoinageFungibilityDistribution(
            bands: ladder.map { band in
                let total = totals[band] ?? 0

                return .init(
                    id: band,
                    share: peak > 0 ? NSDecimalNumber(decimal: total / peak).doubleValue : 0,
                    total: total > 0 ? formatted(total) : nil
                )
            }
        )
    }
}
