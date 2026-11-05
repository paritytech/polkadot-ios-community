import Foundation

final class DeviceTransferReceiverWireframe {
    private weak var observer: RootStateObserving?

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension DeviceTransferReceiverWireframe: DeviceTransferReceiverWireframeProtocol {
    /// Finalize saved this phone as active, so the root routes to the dashboard.
    func complete() {
        observer?.didSettleInstallationStatus()
    }
}
