import Foundation

extension RuntimeSyncService: RuntimeSyncServiceProtocol {
    func register(chain: ChainModel, with connection: ChainConnection) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        guard let syncInfo = knownChains[chain.chainId] else {
            knownChains[chain.chainId] = SyncInfo(typesURL: chain.types?.url, connection: connection)
            return
        }

        if syncInfo.typesURL != chain.types?.url {
            knownChains[chain.chainId] = SyncInfo(typesURL: chain.types?.url, connection: connection)

            performSync(for: chain.chainId, shouldSyncTypes: true)
        }
    }

    func unregisterIfExists(chainId: ChainModel.Id) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        clearOperations(for: chainId)
        knownChains[chainId] = nil
    }

    func apply(version: RuntimeVersion, for chainId: ChainModel.Id) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        clearOperations(for: chainId)

        performSync(for: chainId, shouldSyncTypes: true, newVersion: version)
    }

    func hasChain(with chainId: ChainModel.Id) -> Bool {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        return knownChains[chainId] != nil
    }

    func isChainSyncing(_ chainId: ChainModel.Id) -> Bool {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        return (syncingChains[chainId] != nil) || (retryAttempts[chainId] != nil)
    }
}
