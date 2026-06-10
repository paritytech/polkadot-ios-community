import Foundation

protocol RootStateObserving: AnyObject {
    func didCreateWallets()
    func didRestoreWallets()
    func didDecideBroken()
    func didClaimUsername()
    func didDecideClaim()
    func didSelectTheme()
    func proceedAfterWeb3Summit()
}
