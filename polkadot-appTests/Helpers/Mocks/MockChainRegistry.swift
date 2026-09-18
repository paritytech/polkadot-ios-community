import Foundation
import Operation_iOS
import SubstrateSdk
import ChainRegistry

@testable import polkadot_app

final class MockChainRegistry: ChainRegistryProtocol {
    var chainsByGenesis: [String: ChainModel] = [:]
    var runtimeProviders: [String: RuntimeProviderProtocol] = [:]
    var connectionsByChainId: [ChainModel.Id: ChainConnection] = [:]

    /// Chains delivered to a new subscriber. Empty by default, so subscribing stays a no-op.
    var chainsOnSubscribe: [ChainModel] = []

    var availableChainIds: Set<ChainModel.Id>? { nil }
    var allAvailableChains: [ChainModel] { Array(chainsByGenesis.values) }

    func getChain(for _: ChainModel.Id) -> ChainModel? { nil }
    func getChainByGenesis(for genesisHash: ChainModel.Id) -> ChainModel? { chainsByGenesis[genesisHash] }
    func getConnection(for chainId: ChainModel.Id) -> ChainConnection? { connectionsByChainId[chainId] }
    func getOneShotConnection(for _: ChainModel.Id) -> JSONRPCEngine? { nil }
    func retainConnections(_: ConnectionRetainScope) -> ConnectionRetainToken { ConnectionRetainToken() }
    func getRuntimeProvider(for chainId: ChainModel.Id) -> RuntimeProviderProtocol? { runtimeProviders[chainId] }
    func switchSync(mode _: ChainSyncMode, chainId _: ChainModel.Id) throws {}

    func chainsSubscribe(
        _: AnyObject,
        runningInQueue queue: DispatchQueue,
        updateClosure: @escaping ([DataProviderChange<ChainModel>]) -> Void
    ) {
        guard !chainsOnSubscribe.isEmpty else { return }

        let changes = chainsOnSubscribe.map { DataProviderChange<ChainModel>.insert(newItem: $0) }

        queue.async {
            updateClosure(changes)
        }
    }

    func chainsUnsubscribe(_: AnyObject) {}
    func subscribeChainState(_: ConnectionStateSubscription, chainId _: ChainModel.Id) {}
    func unsubscribeChainState(_: ConnectionStateSubscription, chainId _: ChainModel.Id) {}
    func syncUp() {}
}
