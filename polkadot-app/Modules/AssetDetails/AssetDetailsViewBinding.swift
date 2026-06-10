import Foundation
import PolkadotUI
import SwiftUI
import UIKit
import UIKitExt

final class AssetDetailsViewBinding: AssetDetailsViewProtocol {
    let viewModel: AssetDetailsViewModel
    weak var navigationHost: ControllerBackedProtocol?
    var animatesBackupNotificationUpdates = true

    private var cardCreateModel: WalletCardCreateViewModel?
    private var amount: String?
    private var lockedAmountString: String?

    init(viewModel: AssetDetailsViewModel) {
        self.viewModel = viewModel
    }

    var isSetup: Bool {
        navigationHost?.isSetup ?? false
    }

    var controller: UIViewController {
        guard let controller = navigationHost?.controller else {
            assertionFailure("AssetDetailsViewBinding requires a navigation host before presenting UI")
            return UIViewController()
        }

        return controller
    }

    func bind(to presenter: AssetDetailsPresenterProtocol) {
        viewModel.onSendMoney = { [weak presenter] in
            presenter?.onSendMoney()
        }

        viewModel.onAddMoney = { [weak presenter] in
            presenter?.onAddMoney()
        }

        viewModel.onFundingCompleted = { [weak presenter] in
            presenter?.onFundingCompletedAction()
        }

        viewModel.onFundingFailed = { [weak presenter] in
            presenter?.onFundingFailedAction()
        }

        viewModel.onBackupSync = { [weak presenter] in
            presenter?.onBackupSync()
        }

        viewModel.onBackupCancel = { [weak presenter] in
            presenter?.onBackupCancel()
        }

        viewModel.onBackupWhyUpdate = { [weak presenter] in
            presenter?.onBackupWhyUpdate()
        }

        #if TESTNET_FEATURE
            viewModel.onTopUp = { [weak presenter] in
                presenter?.onTopUp()
            }

            viewModel.onMakeAllVouchersReady = { [weak presenter] in
                presenter?.onMakeAllVouchersReady()
            }
        #endif
    }

    func didSetCards(viewModels: [WalletCardCreateViewModel]) {
        cardCreateModel = viewModels.first
        emitCardUpdate()
    }

    func didReceiveData(viewModel: WalletCardDataViewModel, index _: Int) {
        switch viewModel {
        case let .token(balance):
            amount = balance.amount
        }

        emitCardUpdate()
    }

    func didReceive(lockedAmount: BalanceViewModelProtocol?) {
        defer {
            emitCardUpdate()
        }

        guard let lockedAmount else {
            lockedAmountString = nil
            return
        }

        lockedAmountString = String(localized: .balanceOnhold(amount: lockedAmount.amount))
    }

    #if TESTNET_FEATURE
        func didReceive(coinageBreakdown: CoinageBalanceBreakdownViewModel) {
            viewModel.coinageBreakdown = coinageBreakdown
        }
    #endif

    func didReceive(fundingStates: [AssetFundingStatusView.FundingState]) {
        viewModel.fundingStates = fundingStates
    }

    func didReceive(isRecoveryInProgress: Bool) {
        viewModel.isUpdating = isRecoveryInProgress
    }

    func didShowBackupNotification() {
        guard animatesBackupNotificationUpdates else {
            viewModel.showsBackupNotification = true
            return
        }

        withAnimation(.easeInOut) {
            viewModel.showsBackupNotification = true
        }
    }

    func didHideBackupNotification() {
        withAnimation(.easeInOut) {
            viewModel.showsBackupNotification = false
        }
    }

    #if TESTNET_FEATURE
        func didReceive(faucetLoading: Bool) {
            viewModel.isFaucetInProgress = faucetLoading
        }
    #endif

    private func emitCardUpdate() {
        viewModel.balanceCardModel = .init(
            balance: amount,
            lockedAmount: lockedAmountString
        )
    }
}
