import Foundation

@MainActor
protocol RootStateObserving: AnyObject {
    func didCreateWallets()
    func didRestoreWallets()
    func didDecideBroken()
    func didClaimUsername()
    func didDecideClaim()
    func didSelectTheme()
    func didSettleInstallationStatus()
    func didConfirmDeviceTransfer(_ request: DeviceTransferRequest)
}
