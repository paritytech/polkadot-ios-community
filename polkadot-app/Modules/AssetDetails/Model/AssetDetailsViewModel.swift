import Observation
import PolkadotUI
import Combine
import SubstrateSdk
import Foundation

#if TESTNET_FEATURE
    struct CoinageBalanceBreakdownViewModel {
        /// Bare amounts, no symbol: the headline carries ``symbol`` once, in small type, and the
        /// three figures below it are read against that.
        let totalBalance: String
        let availableNowBalance: String
        let gainingPrivacyBalance: String
        let pendingBalance: String
        let symbol: String
        let composition: CoinageCompositionBar.Model
        /// Coins and vouchers in one list, already ordered for display.
        let holdings: [CoinageHoldingViewModel]
    }
#endif

#if TESTNET_FEATURE
    /// A single coin or voucher row: its value, and a number-free status depiction.
    struct CoinageHoldingViewModel: Identifiable {
        let id: String
        /// The bare value, no currency symbol. Nil until the denomination context is known.
        let amount: String?
        let status: Status

        enum Status: Equatable {
            case coin(CoinStatusView.Model)
            case voucher(VoucherStatusView.Model)
        }
    }
#endif

protocol AssetDetailsViewModelProtocol: Observation.Observable {
    var balanceCardModel: AssetDetailsBalanceCard.ViewModel? { get set }
    var showsBackupNotification: Bool { get set }
    #if TESTNET_FEATURE
        var coinageBreakdown: CoinageBalanceBreakdownViewModel? { get set }
    #endif
    var fundingStates: [AssetFundingStatusView.FundingState] { get set }
    var isFundingExpanded: Bool { get set }
    var isUpdating: Bool { get set }

    var onAddMoney: (() -> Void)? { get set }
    var onSendMoney: (() -> Void)? { get set }
    var onFundingCompleted: (() -> Void)? { get set }
    var onFundingFailed: (() -> Void)? { get set }
    var onBackupSync: (() -> Void)? { get set }
    var onBackupCancel: (() -> Void)? { get set }
    var onBackupWhyUpdate: (() -> Void)? { get set }

    var isTopUpInProgress: Bool { get set }
    var onTopUp: (() -> Void)? { get set }

    #if TESTNET_FEATURE
        var isTestnetTopUpInProgress: Bool { get set }
        var onTestnetTopUp: (() -> Void)? { get set }
        var onMakeAllVouchersReady: (() -> Void)? { get set }
        var usesFixtureCoinage: Bool { get set }
        var onToggleFixtureCoinage: (() -> Void)? { get set }
    #endif
}

@Observable
class AssetDetailsViewModel: AssetDetailsViewModelProtocol {
    var balanceCardModel: AssetDetailsBalanceCard.ViewModel?
    var showsBackupNotification: Bool = false
    #if TESTNET_FEATURE
        var coinageBreakdown: CoinageBalanceBreakdownViewModel?
    #endif
    var fundingStates: [AssetFundingStatusView.FundingState] = []
    var isFundingExpanded: Bool = false
    var isUpdating: Bool = false

    var onAddMoney: (() -> Void)?
    var onSendMoney: (() -> Void)?
    var onFundingCompleted: (() -> Void)?
    var onFundingFailed: (() -> Void)?
    var onBackupSync: (() -> Void)?
    var onBackupCancel: (() -> Void)?
    var onBackupWhyUpdate: (() -> Void)?

    var isTopUpInProgress: Bool = false
    var onTopUp: (() -> Void)?

    #if TESTNET_FEATURE
        var isTestnetTopUpInProgress: Bool = false
        var onTestnetTopUp: (() -> Void)?
        var onMakeAllVouchersReady: (() -> Void)?
        var usesFixtureCoinage: Bool = false
        var onToggleFixtureCoinage: (() -> Void)?
    #endif
}
