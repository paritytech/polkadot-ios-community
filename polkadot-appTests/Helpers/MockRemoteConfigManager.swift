import Foundation
import Operation_iOS

@testable import polkadot_app

final class MockRemoteConfigManager: RemoteConfigManaging {
    var chainsToReturn: [RemoteChainModel] = []
    var errorToThrow: Error?
    var web3SummitGateMode: String?
    var web3SummitStartGate: String?
    var collectiblesEnabled = false
    var remoteConfig = RemoteAppConfig(
        identityBackendUrl: URL(string: "https://polkadot-app-stg.parity.io/"),
        ipfsGatewayUrl: nil,
        gameDashboardUrl: nil,
        dotNsResolver: nil,
        web3SummitDotNsUrl: nil,
        web3SummitContractAddress: nil
    )

    func fetchRemoteConfigValues() {}

    func asyncWaitRemoteConfig() async throws -> RemoteAppConfig {
        if let error = errorToThrow {
            throw error
        }
        return remoteConfig
    }

    func syncedWeb3SummitGateMode() -> String? {
        web3SummitGateMode
    }

    func syncedWeb3SummitStartGate() -> String? {
        web3SummitStartGate
    }

    func syncedCollectiblesEnabled() -> Bool {
        collectiblesEnabled
    }

    func asyncWaitChainsForRemoteConfigValues() -> CompoundOperationWrapper<[RemoteChainModel]> {
        if let error = errorToThrow {
            return CompoundOperationWrapper.createWithError(error)
        }
        return CompoundOperationWrapper.createWithResult(chainsToReturn)
    }

    func asyncWaitXcmTransfers<T: Decodable>() -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper.createWithError(NSError(domain: "mock", code: 0))
    }

    func asyncWaitXcmGeneralConfig<T: Decodable>() -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper.createWithError(NSError(domain: "mock", code: 0))
    }

    func asyncWaitW3sMerchants<T: Decodable>() -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper.createWithError(NSError(domain: "mock", code: 0))
    }
}
