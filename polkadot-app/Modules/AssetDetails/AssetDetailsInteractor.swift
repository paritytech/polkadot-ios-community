import UIKit
import Operation_iOS
import OperationExt
import Foundation
import SubstrateSdk
import StructuredConcurrency
import Coinage
import CommonService
import KeyDerivation
import AsyncExtensions
import AsyncAlgorithms

final class AssetDetailsInteractor: AnyProviderAutoCleaning {
    weak var presenter: AssetDetailsInteractorOutputProtocol?

    let depositWallet: WalletManaging
    let priceLocalSubscriptionFactory: PriceProviderFactoryProtocol
    let chainAsset: ChainAsset

    private let fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol
    private var fiatOnrampTrackingTask: Task<Void, Never>?

    private var balanceSubscriptionTask: Task<Void, Error>?
    private var priceProvider: StreamableProvider<PriceData>?
    private var priceSubscriptionTask: Task<Void, Never>?
    private let coinageService: CoinageServicing
    private let coinageBackupSyncService: any CoinageBackupSyncServicing
    private let balanceSyncStateStorage: BalanceSyncStateStoring
    private let eventCenter: EventCenterProtocol

    private var recoveryStateTask: Task<Void, Error>?

    #if TESTNET_FEATURE
        private var coinageSubscriptionTask: Task<Void, Never>?
        private let coinProvider: StreamableProvider<Coin>
        private let voucherProvider: StreamableProvider<Voucher>

        let voucherRepository: AnyDataProviderRepository<Voucher>

        var topupService: TopUpService?
        var faucetTask: Task<Void, Error>?
    #endif

    init(
        depositWallet: WalletManaging,
        priceLocalSubscriptionFactory: PriceProviderFactoryProtocol,
        fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol,
        chainAsset: ChainAsset,
        coinageService: CoinageServicing,
        coinageBackupSyncService: any CoinageBackupSyncServicing,
        balanceSyncStateStorage: BalanceSyncStateStoring,
        coinProvider: StreamableProvider<Coin>,
        voucherProvider: StreamableProvider<Voucher>,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        eventCenter: EventCenterProtocol = EventCenter.shared
    ) {
        self.depositWallet = depositWallet
        self.priceLocalSubscriptionFactory = priceLocalSubscriptionFactory
        self.fiatOnrampTrackingService = fiatOnrampTrackingService
        self.chainAsset = chainAsset
        self.coinageService = coinageService
        self.coinageBackupSyncService = coinageBackupSyncService
        self.balanceSyncStateStorage = balanceSyncStateStorage
        self.eventCenter = eventCenter
        #if TESTNET_FEATURE
            self.coinProvider = coinProvider
            self.voucherProvider = voucherProvider

            self.voucherRepository = voucherRepository
        #endif
    }

    deinit {
        fiatOnrampTrackingTask?.cancel()
        balanceSubscriptionTask?.cancel()
        recoveryStateTask?.cancel()
        priceSubscriptionTask?.cancel()
        #if TESTNET_FEATURE
            coinageSubscriptionTask?.cancel()
        #endif
    }
}

extension AssetDetailsInteractor: AssetDetailsInteractorInputProtocol {
    func setup() {
        if balanceSyncStateStorage.isRestorePending {
            Task { @MainActor [weak self] in
                self?.presenter?.didCompleteRecovery()
            }
        }

        eventCenter.add(observer: self)
        subscribeToFiatOnrampTracking()
        subscribeToPrice()
        subscribeToBalances()
        subscribeToRecoveryState()

        #if TESTNET_FEATURE
            subscribeToCoinage()
        #endif
    }

    func triggerSync() {
        coinageBackupSyncService.triggerRecovery()
    }

    func cancelBackupNotification() {
        balanceSyncStateStorage.isRestorePending = false
    }

    func removeCompletedFiatOnrampTransactions() {
        fiatOnrampTrackingService.removeCompletedTransactions()
    }

    func removeFailedFiatOnrampTransactions() {
        fiatOnrampTrackingService.removeFailedTransactions()
    }

    #if TESTNET_FEATURE
        func topUp() {
            faucetTask?.cancel()
            faucetTask = Task { [weak presenter, topupService, coinageService] in
                guard let topupService else {
                    return
                }
                do {
                    guard let amount = Decimal(5).toSubstrateAmount(precision: chainAsset.asset.decimalPrecision) else {
                        return
                    }

                    try await topupService.topUp(depositWallet, amount: .plank(amount))
                    try await coinageService.loadVouchers(amount: amount, externalAssetHolder: depositWallet)
                    await presenter?.didCompleteTopUp(.success(()))
                } catch {
                    await presenter?.didCompleteTopUp(.failure(error))
                }
            }
        }

        func makeAllVouchersReady() {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let vouchers = try await voucherRepository
                        .fetchAllOperation(with: RepositoryFetchOptions())
                        .asyncExecute()

                    let updatedVouchers = vouchers.map { voucher in
                        guard voucher.readyAt > .now else { return voucher }

                        return Voucher(
                            exponent: voucher.exponent,
                            derivationIndex: voucher.derivationIndex,
                            allocatedAt: voucher.allocatedAt,
                            readyAt: .now,
                            remoteState: voucher.remoteState
                        )
                    }

                    try await voucherRepository
                        .saveOperation({ updatedVouchers }, { [] })
                        .asyncExecute()
                } catch {
                    Logger.shared.error("Failed to make all vouchers ready: \(error)")
                }
            }
        }

        private func subscribeToCoinage() {
            coinageSubscriptionTask?.cancel()
            coinageSubscriptionTask = Task { [weak self, coinProvider, voucherProvider] in
                let coinsStream = coinProvider.asyncStream()
                    .scan([String: Coin]()) { dict, changes in changes.mergeToDict(dict) }
                let vouchersStream = voucherProvider.asyncStream()
                    .scan([String: Voucher]()) { dict, changes in changes.mergeToDict(dict) }

                do {
                    for try await (coinsDict, vouchersDict) in combineLatest(coinsStream, vouchersStream) {
                        let coins = Array(coinsDict.values)
                        let vouchers = Array(vouchersDict.values)
                        await self?.presenter?.didReceive(coins: coins, vouchers: vouchers)
                    }
                } catch {
                    Logger.shared.error("Coinage subscription failed: \(error)")
                }
            }
        }
    #endif

    private func subscribeToBalances() {
        balanceSubscriptionTask?.cancel()
        balanceSubscriptionTask = Task { [weak self] in
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    guard let stream = try await self?.coinageService.coinageBalanceService().totalBalanceStream
                    else { return }
                    do {
                        for try await total in stream {
                            try Task.checkCancellation()
                            await self?.presenter?.didReceive(balance: total.balanceInDecimal())
                        }
                    } catch {
                        Logger.shared.error("Total balance stream failed: \(error)")
                    }
                }

                group.addTask { [weak self] in
                    guard let stream = try await self?.coinageService.coinageBalanceService().lockedBalanceStream
                    else { return }
                    do {
                        for try await locked in stream {
                            try Task.checkCancellation()
                            await self?.presenter?.didReceive(lockedAmount: locked.balanceInDecimal())
                        }
                    } catch {
                        Logger.shared.error("Locked balance stream failed: \(error)")
                    }
                }
            }
        }
    }
}

private extension AssetDetailsInteractor {
    func subscribeToRecoveryState() {
        recoveryStateTask?.cancel()
        recoveryStateTask = Task { [weak presenter, coinageBackupSyncService] in
            let stream = coinageBackupSyncService.stateStream
            for try await state in stream {
                switch state {
                case .inProgress:
                    await presenter?.didReceive(isRecoveryInProgress: true)
                case let .failed(error):
                    await presenter?.didReceive(isRecoveryInProgress: false)
                    await presenter?.didFail(recovery: error)
                case .idle:
                    await presenter?.didReceive(isRecoveryInProgress: false)
                case .completed:
                    await presenter?.didReceive(isRecoveryInProgress: false)
                }
            }
        }
    }

    func subscribeToFiatOnrampTracking() {
        fiatOnrampTrackingTask?.cancel()
        fiatOnrampTrackingTask = Task { [weak self] in
            guard let self else {
                return
            }

            let stream = await fiatOnrampTrackingService.subscribeToTransactionStatuses()

            do {
                for try await statuses in stream {
                    await presenter?.didReceive(fiatOnrampStatuses: statuses)
                }
            } catch {
                // No-op: tracking updates are best-effort
            }
        }
    }

    private func subscribeToPrice() {
        guard let priceId = chainAsset.asset.priceId else {
            return
        }
        priceProvider = priceLocalSubscriptionFactory.getPriceStreamableProvider(
            for: priceId,
            currency: .usd
        )

        priceSubscriptionTask?.cancel()
        priceSubscriptionTask = Task { [weak self] in
            guard let self, let priceProvider else { return }
            do {
                for try await changes in priceProvider.asyncStream() {
                    let price = changes.reduceToLastChange()
                    await MainActor.run {
                        self.presenter?.didReceive(price: price)
                    }
                }
            } catch {
                Logger.shared.error("Price subscription failed: \(error)")
            }
        }
    }
}

extension AssetDetailsInteractor: EventVisitorProtocol {
    func processBalanceSyncState(event _: BalanceSyncState) {
        let pending = balanceSyncStateStorage.isRestorePending
        Task { @MainActor [weak self] in
            if pending {
                self?.presenter?.didCompleteRecovery()
            } else {
                self?.presenter?.didClearBackupNotification()
            }
        }
    }
}
