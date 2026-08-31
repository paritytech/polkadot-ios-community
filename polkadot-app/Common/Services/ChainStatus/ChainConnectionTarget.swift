import Foundation
import ChainRegistry
import PolkadotUI

enum ChainConnectionTarget: CaseIterable {
    case chat
    case bulletin
    case assethub

    var chainId: ChainModel.Id {
        switch self {
        case .chat:
            AppConfig.Chains.chatChain
        case .bulletin:
            AppConfig.Chains.bulletInChain
        case .assethub:
            AppConfig.Chains.assethubChain
        }
    }

    /// Stands in until chain data loads; chain names come from the registry and are not localized.
    var fallbackTitle: String {
        switch self {
        case .chat:
            "Chat"
        case .bulletin:
            "Bulletin"
        case .assethub:
            "AssetHub"
        }
    }
}

extension NetworkStatus {
    var connectionState: ChainConnectionState {
        switch self {
        case .connected:
            .connected
        case .connecting:
            .connecting
        case .waitingForNetwork:
            .offline
        }
    }
}

extension ChainConnectionState {
    var localizedTitle: String {
        switch self {
        case .connected:
            String(localized: .Common.chainConnectionStatusConnected)
        case .connecting:
            String(localized: .Common.chainConnectionStatusConnecting)
        case .offline:
            String(localized: .Common.chainConnectionStatusOffline)
        }
    }

    func localizedLatency(_ latency: Duration?) -> String? {
        guard self == .connected, let latency else {
            return nil
        }

        return String(localized: .Common.chainConnectionStatusLatency(latency.roundedMilliseconds))
    }
}

private extension Duration {
    var roundedMilliseconds: Int {
        let attosecondsPerMillisecond = 1e15
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / attosecondsPerMillisecond

        return Int(milliseconds.rounded())
    }
}
