import Foundation

final class Web3SummitSpaWireframe: Web3SummitSpaWireframeProtocol {
    let observer: RootStateObserving

    init(observer: RootStateObserving) {
        self.observer = observer
    }

    func proceed() {
        observer.proceedAfterWeb3Summit()
    }
}
