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

    /// Deliberately not the registry's chain name — those are long ("Polkadot People") and vary by
    /// build arm, which reads badly under a 40pt ring. Not localized, as chain names never were.
    var title: String {
        switch self {
        case .chat:
            "Individuality"
        case .bulletin:
            "Bulletin"
        case .assethub:
            "Asset Hub"
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
}
