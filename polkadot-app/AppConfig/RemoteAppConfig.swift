import Foundation

// Built from individual Firebase RemoteConfig keys:
//   identity_backend_url, ipfs_gateway_url, game_dashboard_url, dot_ns_config, web3summit_config
// Each field nil if the corresponding key is missing or empty.
struct RemoteAppConfig {
    let identityBackendUrl: URL?
    let ipfsGatewayUrl: URL?
    let gameDashboardUrl: URL?
    let dotNsResolver: String?
    let web3SummitDotNsUrl: URL?
    let web3SummitContractAddress: String?
}
