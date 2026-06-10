import Foundation

enum Web3SummitGateMode: String {
    case verificationDisabled = "VERIFICATION_DISABLED"
    case verificationEnabled = "VERIFICATION_ENABLED"
    case verificationEnabledSkippable = "VERIFICATION_ENABLED_SKIPPABLE"
    case ended = "W3S_ENDED"
}

protocol Web3SummitGateModeProviding {
    func current() -> Web3SummitGateMode
}

final class Web3SummitGateModeProvider: Web3SummitGateModeProviding {
    private let remoteConfig: RemoteConfigManaging

    init(remoteConfig: RemoteConfigManaging) {
        self.remoteConfig = remoteConfig
    }

    func current() -> Web3SummitGateMode {
        guard
            let raw = remoteConfig.syncedWeb3SummitGateMode(),
            let mode = Web3SummitGateMode(rawValue: raw)
        else {
            return .verificationEnabled
        }

        return mode
    }
}
