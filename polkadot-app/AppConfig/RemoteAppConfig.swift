import Foundation

// Built from individual Firebase RemoteConfig keys:
//   identity_backend_url, ipfs_gateway_url, game_dashboard_url, dot_ns_config, coinage_instance_id
// Each field nil if the corresponding key is missing or empty.
struct RemoteAppConfig {
    let identityBackendUrl: URL?
    let ipfsGatewayUrl: URL?
    let gameDashboardUrl: URL?
    let dotNsResolver: String?
    let dotNsProtocolRegistry: String?
    /// Absent in payloads published before manifest support, which disables manifest
    /// resolution and leaves legacy resolution working.
    let dotNsNameRegistry: String?
    /// Absent until remote config publishes the key; consumers fall back to instance 0,
    /// which the runtime creates at genesis for the external asset.
    let coinageInstanceId: UInt32?
}

extension RemoteAppConfig {
    var isValid: Bool {
        var result = identityBackendUrl != nil
            && ipfsGatewayUrl != nil
            && dotNsResolver != nil
            && dotNsProtocolRegistry != nil

        #if TESTNET_FEATURE
            result = result && gameDashboardUrl != nil
        #endif

        return result
    }
}
