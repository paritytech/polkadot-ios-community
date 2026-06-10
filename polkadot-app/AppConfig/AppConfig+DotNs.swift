import Foundation
import Products

extension AppConfig {
    enum KnownIPFS {
        static var main: URL! {
            AppConfigProvider.shared.getRemoteConfig()!.ipfsGatewayUrl
        }
    }

    enum DotNs {
        private static var dotNsResolverAddress: String {
            AppConfigProvider.shared.getRemoteConfig()!.dotNsResolver!
        }

        static let dotNsBrowse = "browse.dot"
        static let dotNsGameWebview = "game-webview.dot"
        static let dotNsCollectibles = "collectibles-webview.dot"

        static func config() throws -> DotNsConfig {
            let address = try Self.dotNsResolverAddress.fromHex()

            return DotNsConfig(
                contractsChainId: AppConfig.Chains.assethubChain,
                resolverContractAddress: address,
                ipfsGatewayBaseUrl: AppConfig.KnownIPFS.main
            )
        }
    }
}
