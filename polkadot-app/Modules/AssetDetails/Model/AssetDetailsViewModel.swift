import Observation
import PolkadotUI
import Combine
import SubstrateSdk
import Foundation

struct CoinageBalanceBreakdownViewModel {
    /// Bare amounts, no symbol: the headline carries ``symbol`` once, in small type, and the
    /// two figures below it are read against that.
    let totalBalance: String
    let availableNowBalance: String
    let gainingPrivacyBalance: String
    let symbol: String
    let composition: CoinageCompositionBar.Model
    /// Coins and vouchers in one list, already ordered for display. What the screen draws.
    let holdings: [CoinageHoldingViewModel]
    /// Alternative depictions, kept alongside the live one so a design variant is a one-line
    /// change in ``CoinageDetailsView`` rather than a revert.
    let groups: [CoinageHoldingGroupViewModel]
    let distribution: CoinageFungibilityDistribution
    let matrix: CoinageHoldingMatrix
    /// Every holding, in list order, for the table depiction.
    let table: [CoinageTableView.Coin]
}

/// A single coin or voucher row: its value, and a number-free status depiction.
struct CoinageHoldingViewModel: Identifiable {
    let id: String
    /// The bare value, no currency symbol. Nil until the denomination context is known.
    let amount: String?
    let status: CoinageHoldingStatus
}

/// Everything that draws one depiction: the depiction itself, the values that share it, and what
/// they come to.
struct CoinageHoldingGroupViewModel: Identifiable {
    let id: String
    let status: CoinageHoldingStatus
    /// Values in the group, descending, repeats folded into a count. Empty until the denomination
    /// context is known.
    let amounts: String
    /// How many holdings the group stands for.
    let count: Int
    /// Value against the largest group, in `0...1`. Drives how thick the bar is drawn, so the
    /// mark carries value as well as standing.
    let share: Double
    /// What the group comes to, bare, no currency symbol.
    let total: String?
}

enum CoinageHoldingStatus: Equatable {
    case coin(CoinStatusView.Model)
    case voucher(VoucherStatusView.Model)
}

/// Holdings crossed against the fungibility ladder: one row per denomination, one column per
/// band, so the joint picture is visible rather than one axis collapsed into the other.
struct CoinageHoldingMatrix: Equatable {
    struct Row: Equatable, Identifiable {
        /// The denomination's exponent, which is also its order.
        let id: Int16
        let amount: String
        /// Holdings in each band, in the same order as ``CoinageHoldingMatrix/bands``.
        let counts: [Int]
    }

    /// Ladder ids, least fungible first.
    let bands: [Int]
    let rows: [Row]

    static let empty = CoinageHoldingMatrix(bands: [], rows: [])
}

/// The balance laid out along the fungibility ladder, least fungible first.
///
/// Every band is present whether or not anything stands in it, so the shape is comparable from one
/// reading to the next and the empty stretch ahead of a holding is visible.
struct CoinageFungibilityDistribution: Equatable {
    struct Band: Equatable, Identifiable {
        /// ``CoinageFungibilityDistribution/unknownBand`` for holdings with no recycler record,
        /// otherwise the fungibility bucket.
        let id: Int
        /// Height against the fullest band, in `0...1`.
        let share: Double
        /// Bare total, no currency symbol. Nil when nothing stands here.
        let total: String?
    }

    static let unknownBand = -1

    let bands: [Band]

    static let empty = CoinageFungibilityDistribution(bands: [])
}

protocol AssetDetailsViewModelProtocol: Observation.Observable {
    var balanceCardModel: AssetDetailsBalanceCard.ViewModel? { get set }
    var showsBackupNotification: Bool { get set }
    /// This installation's on-chain registration has not landed in the expected time (D4).
    var showsAccountBackupPending: Bool { get set }
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
    var isWithdrawInProgress: Bool { get set }
    var onWithdraw: (() -> Void)? { get set }

    var coinageBreakdown: CoinageBalanceBreakdownViewModel? { get set }
    #if TESTNET_FEATURE
        var isTestnetTopUpInProgress: Bool { get set }
        var onTestnetTopUp: (() -> Void)? { get set }
    #endif
}

@Observable
class AssetDetailsViewModel: AssetDetailsViewModelProtocol {
    var balanceCardModel: AssetDetailsBalanceCard.ViewModel?
    var showsBackupNotification: Bool = false
    var showsAccountBackupPending: Bool = false
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
    var isWithdrawInProgress: Bool = false
    var onWithdraw: (() -> Void)?

    var coinageBreakdown: CoinageBalanceBreakdownViewModel?
    #if TESTNET_FEATURE
        var isTestnetTopUpInProgress: Bool = false
        var onTestnetTopUp: (() -> Void)?
    #endif
}
