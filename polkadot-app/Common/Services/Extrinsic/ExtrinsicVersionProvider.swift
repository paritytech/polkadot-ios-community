import Foundation
import ChainStore
import SubstrateSdk

protocol ExtrinsicVersionProviding {
    func getExtrinsicVersion(for chainId: ChainId, isSigned: Bool) -> Extrinsic.Version

    /// Per-chain V5 transaction-extension version from remote config; unlisted chains default to 0.
    func extensionVersion(for chainId: ChainId) -> UInt8
}

final class ExtrinsicVersionProvider {
    private let remoteConfig: RemoteConfigManaging

    init(remoteConfig: RemoteConfigManaging = FirebaseApplicationService.shared) {
        self.remoteConfig = remoteConfig
    }
}

extension ExtrinsicVersionProvider: ExtrinsicVersionProviding {
    func getExtrinsicVersion(for chainId: ChainId, isSigned: Bool) -> Extrinsic.Version {
        // The chain decides the format (V4 vs V5); isSigned is retained so AssetHub signed stays V4.
        let usesV5: Bool =
            switch chainId {
            case AppConfig.Chains.usernameChain: true
            case AppConfig.Chains.assethubChain: !isSigned
            default: false
            }

        guard usesV5 else { return .V4 }

        return .V5(extensionVersion: extensionVersion(for: chainId))
    }

    func extensionVersion(for chainId: ChainId) -> UInt8 {
        remoteConfig.syncedTxExtensionVersions()[chainId] ?? 0
    }
}
