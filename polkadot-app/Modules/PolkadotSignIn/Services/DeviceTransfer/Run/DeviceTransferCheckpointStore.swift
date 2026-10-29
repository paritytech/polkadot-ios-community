import Foundation
import Keystore_iOS
import SubstrateSdk

protocol DeviceTransferCheckpointStoring {
    func checkpoint(for senderInstallationId: Data) -> UInt64?
    func save(_ timePoint: UInt64, senderInstallationId: Data)
    func clear()
}

/// The `timePoint` is the sender's clock, so it only counts for the installation that sent it.
final class DeviceTransferCheckpointStore {
    private let settingsManager: SettingsManagerProtocol

    init(settingsManager: SettingsManagerProtocol = SettingsManager.shared) {
        self.settingsManager = settingsManager
    }
}

extension DeviceTransferCheckpointStore: DeviceTransferCheckpointStoring {
    func checkpoint(for senderInstallationId: Data) -> UInt64? {
        guard
            settingsManager.string(for: .deviceTransferCheckpointSender) == senderInstallationId.toHex(),
            let timePoint = settingsManager.integer(for: .deviceTransferCheckpoint)
        else {
            return nil
        }

        return UInt64(timePoint)
    }

    func save(_ timePoint: UInt64, senderInstallationId: Data) {
        settingsManager.set(string: senderInstallationId.toHex(), for: .deviceTransferCheckpointSender)
        settingsManager.set(value: Int(timePoint), for: .deviceTransferCheckpoint)
    }

    func clear() {
        settingsManager.removeValue(for: .deviceTransferCheckpoint)
        settingsManager.removeValue(for: .deviceTransferCheckpointSender)
    }
}
