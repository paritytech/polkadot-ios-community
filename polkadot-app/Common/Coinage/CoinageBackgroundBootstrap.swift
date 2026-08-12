import Foundation
import Coinage
import KeyDerivation
import ChainRegistry

enum CoinageBackgroundBootstrap {
    static func makeRecyclingService(logger: LoggerProtocol) async -> (any CoinageRecyclingServicing)? {
        guard (try? RootEntropyManager.shared.hasRootEntropy()) == true else {
            logger.warning("[BGTask] no root entropy, skipping coinage recycling")
            return nil
        }

        let registry = ChainRegistryFacade.sharedRegistry
        registry.syncUp()

        await registry.asyncWaitChainsSetup(for: [AppConfig.Assets.mainAsset.chainId])

        return ServiceCoordinator.makeBackgroundRecyclingService()
    }
}
