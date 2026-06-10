import Foundation
import UniqueDevice

enum AppAttestProviderResolver {
    static func resolve() -> AppAttestProviding {
        #if DISABLE_AUTH
            return NoAppAttestProvider()
        #else
            let storage = SubstrateDataStorageFacade.shared
            let repositoryFactory = AppAttestRepositoryFactory(storageFacade: storage)
            let providerFactory = AppAttestProviderFactory(
                repositoryFactory: repositoryFactory,
                operationQueue: OperationManagerFacade.sharedDefaultQueue
            )
            return providerFactory.createProvider(with: .appAttest)
        #endif
    }
}
