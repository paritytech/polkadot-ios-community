import Foundation
import PolkadotUI
import Coinage
import UIKitExt

protocol AssetDetailsViewProtocol: ControllerBackedProtocol {
    func didSetCards(viewModels: [WalletCardCreateViewModel])
    func didReceiveData(viewModel: WalletCardDataViewModel, index: Int)
    func didReceive(lockedAmount: BalanceViewModelProtocol?)
    func didReceive(fundingStates: [AssetFundingStatusView.FundingState])
    func didReceive(isRecoveryInProgress: Bool)
    func didShowBackupNotification()
    func didHideBackupNotification()

    #if TESTNET_FEATURE
        func didReceive(coinageBreakdown: CoinageBalanceBreakdownViewModel)
        func didReceive(faucetLoading: Bool)
    #endif
}

protocol AssetDetailsPresenterProtocol: AnyObject {
    func setup()
    func onSendMoney()
    func onAddMoney()
    func onFundingCompletedAction()
    func onFundingFailedAction()
    func onBackupSync()
    func onBackupCancel()
    func onBackupWhyUpdate()

    #if TESTNET_FEATURE
        func onTopUp()
        func onMakeAllVouchersReady()
    #endif
}

protocol AssetDetailsInteractorInputProtocol: AnyObject {
    func setup()
    func removeCompletedFiatOnrampTransactions()
    func removeFailedFiatOnrampTransactions()
    func triggerSync()
    func cancelBackupNotification()

    #if TESTNET_FEATURE
        func topUp()
        func makeAllVouchersReady()
    #endif
}

@MainActor
protocol AssetDetailsInteractorOutputProtocol: AnyObject {
    func didReceive(balance: Decimal)
    func didReceive(lockedAmount: Decimal)

    func didReceive(price: PriceData?)
    func didReceive(fiatOnrampStatuses: Set<FiatOnrampTransactionStatusPayload>)
    func didFail(recovery error: Error)
    func didReceive(isRecoveryInProgress: Bool)
    func didCompleteRecovery()
    func didClearBackupNotification()

    #if TESTNET_FEATURE
        func didReceive(coins: [Coin], vouchers: [Voucher])
        func didCompleteTopUp(_ result: Result<Void, Error>)
    #endif
}

protocol AssetDetailsWireframeProtocol: AlertPresentable, ErrorPresentable, BackupSyncPresentable {
    func showTransfer(from view: ControllerBackedProtocol?, chainAsset: ChainAsset)

    func showAddTokens(from view: ControllerBackedProtocol?)
}
