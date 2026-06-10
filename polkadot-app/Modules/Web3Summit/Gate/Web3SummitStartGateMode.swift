import Foundation

enum Web3SummitStartGateMode: String {
    case started = "STARTED"
    case notStarted = "NOT_STARTED"
}

protocol Web3SummitStartGateProviding {
    func current() -> Web3SummitStartGateMode
}

final class Web3SummitStartGateProvider: Web3SummitStartGateProviding {
    private let remoteConfig: RemoteConfigManaging

    init(remoteConfig: RemoteConfigManaging) {
        self.remoteConfig = remoteConfig
    }

    func current() -> Web3SummitStartGateMode {
        guard
            let raw = remoteConfig.syncedWeb3SummitStartGate(),
            let mode = Web3SummitStartGateMode(rawValue: raw)
        else {
            return .started
        }

        return mode
    }
}
