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

    var expectedBlockTime: Duration {
        switch self {
        case .chat,
             .assethub:
            .seconds(2)
        case .bulletin:
            .seconds(6)
        }
    }

    private var finalityStallBounds: ChainHealthBounds {
        // The score measures time since the finalized head last advanced, sawtoothing from 0 up to
        // roughly the finality interval (measured 2026-09-04: .chat 6s, .assethub 6s, .bulletin 10s).
        // The healthy bound must sit clear of the normal peak or a healthy chain clips into amber
        // on every cycle; 2.5x leaves room for one slow round. The zero bound at 10x marks a genuine
        // stall rather than a hiccup.
        switch self {
        case .chat,
             .assethub:
            ChainHealthBounds(healthy: .seconds(15), zero: .seconds(60))
        case .bulletin:
            ChainHealthBounds(healthy: .seconds(25), zero: .seconds(100))
        }
    }

    var healthThresholds: ChainHealthThresholds {
        ChainHealthThresholds(
            blockAge: ChainHealthBounds(
                healthy: expectedBlockTime * 2,
                zero: expectedBlockTime * 10
            ),
            finalityStall: finalityStallBounds,
            ping: ChainHealthBounds(healthy: .milliseconds(150), zero: .milliseconds(1_000)),
            missingTermGrace: .seconds(45)
        )
    }

    var statusIcon: ChainStatusIcon {
        switch self {
        case .chat:
            .people
        case .bulletin:
            .bulletin
        case .assethub:
            .assetHub
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
