import Foundation

final class InstallationCheckWireframe {
    /// Strong: once the first route is shown, nothing else keeps the root presenter alive.
    private let observer: RootStateObserving

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension InstallationCheckWireframe: InstallationCheckWireframeProtocol {
    /// The root reads the saved status and routes from there.
    func complete() {
        observer.didSettleInstallationStatus()
    }
}
