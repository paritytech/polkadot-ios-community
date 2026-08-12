import Foundation
import SubstrateSdk
import Coinage
import ChainRegistry

protocol WalletFlowContextProtocol {
    var depositService: DepositServiceProtocol { get }
    var fiatOnrampService: FiatOnrampServicing { get }
    var fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol { get }
    var coinageService: CoinageServicing { get }
    var coinageBackupSyncService: CoinageBackupSyncServicing { get }
    var personDataStore: DetermineStatePersonDataStore { get }
    var balanceSyncStateStorage: BalanceSyncStateStoring { get }
    var networkStatusService: NetworkStatusProviding { get }
}

final class WalletFlowContext: WalletFlowContextProtocol {
    let depositService: DepositServiceProtocol
    let fiatOnrampService: FiatOnrampServicing
    let fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol
    let coinageService: CoinageServicing
    let coinageBackupSyncService: CoinageBackupSyncServicing
    let personDataStore: DetermineStatePersonDataStore
    let balanceSyncStateStorage: BalanceSyncStateStoring
    let networkStatusService: NetworkStatusProviding

    init(
        depositService: DepositServiceProtocol,
        fiatOnrampService: FiatOnrampServicing,
        fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol,
        coinageService: CoinageServicing,
        coinageBackupSyncService: CoinageBackupSyncServicing,
        personDataStore: DetermineStatePersonDataStore,
        networkStatusService: NetworkStatusProviding,
        balanceSyncStateStorage: BalanceSyncStateStoring = BalanceSyncStateStorage()
    ) {
        self.depositService = depositService
        self.fiatOnrampService = fiatOnrampService
        self.fiatOnrampTrackingService = fiatOnrampTrackingService
        self.coinageService = coinageService
        self.coinageBackupSyncService = coinageBackupSyncService
        self.personDataStore = personDataStore
        self.networkStatusService = networkStatusService
        self.balanceSyncStateStorage = balanceSyncStateStorage
    }
}
