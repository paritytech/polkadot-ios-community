import Foundation
import Keystore_iOS

protocol Web3SummitVerifiedStoring {
    func isVerified() -> Bool
    func setVerified(_ verified: Bool)
}

final class Web3SummitVerifiedStorage: Web3SummitVerifiedStoring {
    private let settingsManager: SettingsManagerProtocol

    init(settingsManager: SettingsManagerProtocol = SettingsManager.shared) {
        self.settingsManager = settingsManager
    }

    func isVerified() -> Bool {
        settingsManager.value(for: .web3SummitVerified)
    }

    func setVerified(_ verified: Bool) {
        settingsManager.set(value: verified, for: .web3SummitVerified)
    }
}
