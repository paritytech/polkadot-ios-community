import Observation

@Observable
public class DeviceTransferRequestViewModel {
    public var newPhone: DeviceTransferPhone?
    public var onTransfer: (() -> Void)?
    public var onDecline: (() -> Void)?

    public init() {}
}
