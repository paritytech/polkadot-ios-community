import Foundation

final class InstallationCheckWireframe {
    private weak var observer: RootStateObserving?

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension InstallationCheckWireframe: InstallationCheckWireframeProtocol {
    /// The root reads the saved status and routes from there.
    func complete() {
        observer?.didSettleInstallationStatus()
    }
}
