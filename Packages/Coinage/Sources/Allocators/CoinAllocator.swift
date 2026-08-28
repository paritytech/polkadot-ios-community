import Foundation
import SubstrateSdk
import NovaCrypto
import KeyDerivation
import Operation_iOS

protocol CoinAllocating: Actor {
    func allocate(exponent: Int16) async throws -> Coin
}

/// Actor isolation serialises the index counter's read-modify-write, so a single shared instance is
/// the only safe configuration — do not create more than one against the same index store.
actor CoinAllocator: CoinAllocating {
    private let storage: CoinageIndexstoreProtocol
    private let coinRepository: AnyDataProviderRepository<Coin>

    init(
        storage: CoinageIndexstoreProtocol,
        coinRepository: AnyDataProviderRepository<Coin>
    ) {
        self.storage = storage
        self.coinRepository = coinRepository
    }

    /// Allocates a new coin index and persists the coin, so it exists in the database from the
    /// moment it is minted (matching the voucher allocator and the Android model).
    func allocate(exponent: Int16) async throws -> Coin {
        let index = try storage.getNextIndex()
        let coin = Coin(exponent: exponent, derivationIndex: index, age: nil)
        try await coinRepository.saveOperation({ [coin] }, { [] }).asyncExecute()
        return coin
    }
}
