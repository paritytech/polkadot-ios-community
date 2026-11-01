import Observation

/// The old phone's transfer screens, Figma S7, S2, S3, S4 and S8.
public enum DeviceTransferSenderScreen: Equatable {
    case connecting
    case sendingData(progress: Double)
    /// The new phone pulls files at its own pace, so the old phone shows no byte progress.
    case sendingFiles
    /// `nil` once the data is sent: there is no file progress to pause at.
    case reconnecting(progress: Double?)
    case finishing
    case cancelledOnNewPhone
}

@Observable
public class DeviceTransferSenderViewModel {
    public var screen: DeviceTransferSenderScreen = .connecting
    public var newPhone: DeviceTransferPhone?
    public var onCancel: (() -> Void)?
    public var onBackToChats: (() -> Void)?

    public init() {}
}
