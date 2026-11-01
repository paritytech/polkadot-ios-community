import Foundation

final class DeviceTransferReceiverWireframe {
    /// Strong: once the first route is shown, nothing else keeps the root presenter alive.
    private let observer: RootStateObserving

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension DeviceTransferReceiverWireframe: DeviceTransferReceiverWireframeProtocol {
    /// Finalize saved this phone as active, so the root routes to the dashboard.
    func complete() {
        observer.didSettleInstallationStatus()
    }
}
