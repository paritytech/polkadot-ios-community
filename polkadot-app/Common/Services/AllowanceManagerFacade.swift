import Foundation
import Individuality

struct AllowanceManagerFacade {
    let bulletInManager: AllowanceManaging
    let sssManager: AllowanceManaging
    let smartContractManager: AllowanceManaging
}

extension AllowanceManagerFacade {
    static func create(
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry
    ) -> AllowanceManagerFacade? {
        guard
            let bulletInManager = BulletInAllowanceManager.create(chainRegistry: chainRegistry),
            let sssManager = SSStoreAllowanceManager.create(chainRegistry: chainRegistry),
            let smartContractManager = PGASAllowanceManager.create(chainRegistry: chainRegistry)
        else {
            return nil
        }

        return AllowanceManagerFacade(
            bulletInManager: bulletInManager,
            sssManager: sssManager,
            smartContractManager: smartContractManager
        )
    }
}
