import Foundation
import ChainStore
import SubstrateSdk

protocol ExtrinsicVersionProviding {
    func getExtrinsicVersion(for chainId: ChainId, isSigned: Bool) -> Extrinsic.Version
}

final class ExtrinsicVersionProvider {}

extension ExtrinsicVersionProvider: ExtrinsicVersionProviding {
    func getExtrinsicVersion(for chainId: ChainId, isSigned: Bool) -> Extrinsic.Version {
        switch chainId {
        case AppConfig.Chains.usernameChain: .V5(extensionVersion: 0)
        case AppConfig.Chains.assethubChain: isSigned ? .V4 : .V5(extensionVersion: 0)
        default: .V4
        }
    }
}
