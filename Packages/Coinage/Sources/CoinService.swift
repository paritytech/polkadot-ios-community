import Foundation
import Operation_iOS
import StructuredConcurrency

/// Protocol defining coin persistence operations.
///
/// Local coin status is derived from the durability entry graph on read, so this service no longer
/// writes status. The only stored fact it persists beyond identity is `age` and `isOnchain`, both
/// owned by chain sync, written through `save`.
public protocol CoinServiceProtocol: Sendable {
    /// Fetch all coins.
    func fetchAllCoins() async throws -> [Coin]

    /// Save coins to persistent storage.
    func save(coins: [Coin]) async throws
}

public final class CoinService: @unchecked Sendable {
    private let coinRepository: AnyDataProviderRepository<Coin>

    public init(coinRepository: AnyDataProviderRepository<Coin>) {
        self.coinRepository = coinRepository
    }
}

extension CoinService: CoinServiceProtocol {
    public func fetchAllCoins() async throws -> [Coin] {
        try await coinRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }

    public func save(coins: [Coin]) async throws {
        guard !coins.isEmpty else { return }
        try await coinRepository.saveOperation({ coins }, { [] }).asyncExecute()
    }
}
