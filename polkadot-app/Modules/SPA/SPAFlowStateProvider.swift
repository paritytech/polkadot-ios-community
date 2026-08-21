import Foundation
import os
import Products
import ChainRegistry

protocol SPAFlowStateProviding: AnyObject {
    func flowState() -> SPAFlowState
}

final class SPAFlowStateProvider: SPAFlowStateProviding {
    private struct State {
        var flowState: SPAFlowState?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    private let chainRegistry: ChainRegistryProtocol
    private let store: DotNsTldStoring

    init(
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        store: DotNsTldStoring = SettingsDotNsTldStore()
    ) {
        self.chainRegistry = chainRegistry
        self.store = store
    }

    func flowState() -> SPAFlowState {
        if let cached = state.withLock({ $0.flowState }) {
            return cached
        }

        guard let config = try? AppConfig.DotNs.config() else {
            fatalError("DotNs config unavailable - remote config not loaded")
        }

        let contractApi = ReviveDotNsContractApi(
            chainRegistry: chainRegistry,
            configProvider: { config }
        )

        let tldProvider = DotNsTldProvider(
            contractApi: contractApi,
            store: store
        )

        let hostProvider = ProductHostFactory(tldProvider: tldProvider)

        let carFetcher = CarFetcher(gatewayBaseUrl: config.ipfsGatewayBaseUrl)
        let contentStorage = DotNsContentStorage()

        let resolver = DotNsResolver(
            contractApi: contractApi,
            carFetcher: carFetcher,
            contentStorage: contentStorage,
            contentHashCache: ContentHashCache.shared
        )

        let productResolver = ProductResolver(
            dotNsResolver: resolver,
            hostProvider: hostProvider,
            logger: Logger.shared
        )

        let created = SPAFlowState(
            dotNsResolver: resolver,
            hostProvider: hostProvider,
            productResolver: productResolver,
            iconViewModelFactory: ProductIconViewModelFactory(
                dotNsResolver: resolver,
                iconLoader: ProductIconLoader(productResolver: productResolver)
            )
        )

        return state.withLock { state in
            if let cached = state.flowState {
                return cached
            }
            state.flowState = created
            return created
        }
    }
}
