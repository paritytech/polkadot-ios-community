import Foundation
import Products

final class SPAFlowState {
    let dotNsResolver: DotNsResolverProtocol

    init(dotNsResolver: DotNsResolverProtocol) {
        self.dotNsResolver = dotNsResolver
    }

    static func create() -> SPAFlowState? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard
            let config = try? AppConfig.DotNs.config(),
            let connection = chainRegistry.getConnection(for: config.contractsChainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: config.contractsChainId)
        else {
            return nil
        }

        let contractApi = ReviveDotNsContractApi(
            connection: connection,
            runtimeProvider: runtimeProvider,
            config: config
        )
        let carFetcher = CarFetcher(gatewayBaseUrl: config.ipfsGatewayBaseUrl)
        let contentStorage = DotNsContentStorage()

        let resolver = DotNsResolver(
            contractApi: contractApi,
            carFetcher: carFetcher,
            contentStorage: contentStorage,
            contentHashCache: ContentHashCache.shared
        )

        return SPAFlowState(dotNsResolver: resolver)
    }
}
