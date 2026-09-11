import Foundation

// Built from individual Firebase RemoteConfig keys:
//   identity_backend_url, ipfs_gateway_url, game_dashboard_url, dot_ns_config, coinage_instance_id,
//   funding_domain, funding_url, offramp_url
// Each field nil if the corresponding key is missing or empty.
struct RemoteAppConfig {
    let identityBackendUrl: URL?
    let ipfsGatewayUrl: URL?
    let gameDashboardUrl: URL?
    let dotNsResolver: String?
    /// Absent in payloads published before manifest support, which disables manifest
    /// resolution and leaves legacy resolution working.
    let dotNsNameRegistry: String?
    let coinageInstanceId: UInt32?
    /// Legacy label of the funding product. Superseded by `fundingUrl`; kept one release as the
    /// allowlist-label fallback.
    let fundingDomain: String?
    /// Full product URLs (host with TLD, optional path) the CASH card opens for top up and withdraw.
    let fundingUrl: URL?
    let offrampUrl: URL?
}

extension RemoteAppConfig {
    var isValid: Bool {
        var result = identityBackendUrl != nil
            && ipfsGatewayUrl != nil
            && dotNsResolver != nil
            && coinageInstanceId != nil
            && fundingUrl != nil
            && offrampUrl != nil

        #if TESTNET_FEATURE
            result = result && gameDashboardUrl != nil
        #endif

        return result
    }
}
