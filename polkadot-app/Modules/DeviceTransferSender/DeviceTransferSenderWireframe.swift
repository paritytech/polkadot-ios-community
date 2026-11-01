import Foundation

final class DeviceTransferSenderWireframe {
    /// Strong: once the first route is shown, nothing else keeps the root presenter alive.
    private let observer: RootStateObserving

    init(observer: RootStateObserving) {
        self.observer = observer
    }
}

extension DeviceTransferSenderWireframe: DeviceTransferSenderWireframeProtocol {}
