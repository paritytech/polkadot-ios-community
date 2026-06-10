import Foundation
import SubstrateSdk
import NovaCrypto
import KeyDerivation

protocol CoinAllocating: Actor {
    func allocate(exponent: Int16) async throws -> Coin
}

actor CoinAllocator: CoinAllocating {
    private let storage: CoinageIndexstoreProtocol

    init(
        storage: CoinageIndexstoreProtocol,
    ) {
        self.storage = storage
    }

    /// Allocates a new coin index, persists it, and derives the corresponding keypair.
    /// - Parameter exponent: The power-of-two denomination for the new coin.
    /// - Returns: A `Coin` ready for use on-chain.
    func allocate(exponent: Int16) async throws -> Coin {
        let index = try storage.getNextIndex()
        return Coin(
            exponent: exponent,
            derivationIndex: index,
            age: nil
        )
    }
}
