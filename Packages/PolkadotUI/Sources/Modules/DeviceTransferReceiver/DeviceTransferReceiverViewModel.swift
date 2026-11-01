import Observation
import SwiftUI

/// The new phone's transfer screens; the layout picks texts and controls for each.
public enum DeviceTransferReceiverScreen: Equatable {
    case start
    case waiting
    case connecting
    /// `progress` runs 0...1 over the whole transfer.
    case syncing(progress: Double)
    case files(progress: Double, receivedBytes: UInt64, totalBytes: UInt64)
    case reconnecting(progress: Double)
    case finishing
    case done
    case declined
    case cancelledOnOldPhone
    case failed
}

public struct DeviceTransferOldPhone: Equatable {
    public let model: String
    public let operatingSystem: String

    public init(model: String, operatingSystem: String) {
        self.model = model
        self.operatingSystem = operatingSystem
    }
}

@Observable
public class DeviceTransferReceiverViewModel {
    public var screen: DeviceTransferReceiverScreen = .start
    public var oldPhone: DeviceTransferOldPhone?
    public var offersActivation = false
    public var onStart: (() -> Void)?
    public var onCancel: (() -> Void)?
    public var onContinue: (() -> Void)?
    public var onActivate: (() -> Void)?

    public init() {}
}
