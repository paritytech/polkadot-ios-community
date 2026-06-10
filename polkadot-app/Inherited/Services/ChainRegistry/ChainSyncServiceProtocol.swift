import Foundation

protocol ChainSyncServiceProtocol {
    func syncUpChains()
    func updateLocal(chain: ChainModel)
}
