import Foundation
import SubstrateSdk
import NovaCrypto
import KeyDerivation
import Operation_iOS
import StructuredConcurrency

protocol CoinAllocating: Actor {
    func allocate(exponent: Int16, provenance: CoinProvenance) async throws -> Coin
}

/// Hands out the next coin item in the current installation: `max(item) + 1` over what is stored there,
/// so a previous installation's coins never move this installation's counter. The serial queue keeps
/// the read-then-save atomic across suspension points; a single shared instance is the only safe
/// configuration.
actor CoinAllocator: CoinAllocating {
    private let installationRepository: any CoinageInstallationRepositoryProtocol
    private let keyIndexQueries: any CoinageKeyIndexQuerying
    private let coinRepository: AnyDataProviderRepository<Coin>
    private let keyFactory: any CoinKeyDeriving
    private let queue = SerialOperationQueue()

    init(
        installationRepository: any CoinageInstallationRepositoryProtocol,
        keyIndexQueries: any CoinageKeyIndexQuerying,
        coinRepository: AnyDataProviderRepository<Coin>,
        keyFactory: any CoinKeyDeriving
    ) {
        self.installationRepository = installationRepository
        self.keyIndexQueries = keyIndexQueries
        self.coinRepository = coinRepository
        self.keyFactory = keyFactory
    }

    /// Allocates a new coin index and persists the coin — with its on-chain public key cached so the
    /// durability layer never re-derives it — from the moment it is minted.
    func allocate(exponent: Int16, provenance: CoinProvenance) async throws -> Coin {
        try await queue.run { [self] in
            let index = try await nextIndex()
            let coin = try Coin(
                exponent: exponent,
                derivationIndex: index,
                age: nil,
                recyclerFungibility: provenance.recyclerFungibility,
                hops: provenance.hops,
                publicKey: keyFactory.derivePublicKey(index: index)
            )
            try await coinRepository.saveOperation({ [coin] }, { [] }).asyncExecute()
            return coin
        }
    }
}

private extension CoinAllocator {
    func nextIndex() async throws -> CoinageKeyIndex {
        let installation = try await installationRepository.getOrCreateCurrent()
        let item = try await keyIndexQueries.maxCoinItem(in: installation).map { $0 + 1 } ?? 0
        return CoinageKeyIndex(installation: installation, item: item)
    }
}
