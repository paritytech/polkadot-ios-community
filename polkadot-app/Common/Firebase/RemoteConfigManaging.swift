import Foundation
import Operation_iOS

protocol RemoteConfigManaging: AnyObject {
    func fetchRemoteConfigValues()
    func asyncWaitChainsForRemoteConfigValues() -> CompoundOperationWrapper<[RemoteChainModel]>
    func asyncWaitXcmTransfers<T: Decodable>() -> CompoundOperationWrapper<T>
    func asyncWaitXcmGeneralConfig<T: Decodable>() -> CompoundOperationWrapper<T>
    func asyncWaitW3sMerchants<T: Decodable>() -> CompoundOperationWrapper<T>
    func syncedWeb3SummitGateMode() -> String?
    func syncedWeb3SummitStartGate() -> String?
    func syncedCollectiblesEnabled() -> Bool

    func asyncWaitRemoteConfig() async throws -> RemoteAppConfig
}
