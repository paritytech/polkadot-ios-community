import Foundation

final class CheckUsernameWireframe: CheckUsernameWireframeProtocol {
    let observer: RootStateObserving

    init(observer: RootStateObserving) {
        self.observer = observer
    }

    func showMainScreen() {
        observer.didClaimUsername()
    }

    func showClaimUsername() {
        observer.didDecideClaim()
    }
}
