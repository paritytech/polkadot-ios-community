import Foundation
import Operation_iOS
import StructuredConcurrency

/// Protocol defining coin persistence operations.
public protocol CoinServiceProtocol: Sendable {
    /// Fetch all available (unspent) coins.
    func fetchAllCoins() async throws -> [Coin]

    /// Save coins to persistent storage.
    func save(coins: [Coin]) async throws

    /// Mark coins as spent by their identifiers.
    func markSpent(coinIds: [String]) async throws

    /// Mark coins as recycling by their identifiers.
    func markRecycling(coinIds: [String]) async throws

    /// Mark coins as available by their identifiers.
    func markAvailable(coinIds: [String]) async throws

    /// Mark coins as pending transfer by their identifiers.
    func markPendingTransfer(coinIds: [String]) async throws

    /// Mark coins as awaiting minting by a live entry.
    func markPendingMint(coinIds: [String]) async throws

    /// Mark coins as handed off to a peer by their identifiers.
    func markHandedOff(coinIds: [String]) async throws
}

public final class CoinService: @unchecked Sendable {
    private let coinRepository: AnyDataProviderRepository<Coin>
    private let coinStateRepository: AnyDataProviderRepository<Coin>

    public init(
        coinRepository: AnyDataProviderRepository<Coin>,
        coinStateRepository: AnyDataProviderRepository<Coin>
    ) {
        self.coinRepository = coinRepository
        self.coinStateRepository = coinStateRepository
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

    public func markSpent(coinIds: [String]) async throws {
        try await apply(state: .spent, for: coinIds)
    }

    public func markRecycling(coinIds: [String]) async throws {
        try await apply(state: .recycling, for: coinIds)
    }

    public func markAvailable(coinIds: [String]) async throws {
        try await apply(state: .available, for: coinIds)
    }

    public func markPendingTransfer(coinIds: [String]) async throws {
        try await apply(state: .pendingTransfer, for: coinIds)
    }

    public func markPendingMint(coinIds: [String]) async throws {
        try await apply(state: .pendingMint, for: coinIds)
    }

    public func markHandedOff(coinIds: [String]) async throws {
        try await apply(state: .handedOff, for: coinIds)
    }
}

private extension CoinService {
    func apply(
        state: Coin.State,
        for identifiers: [String]
    ) async throws {
        guard !identifiers.isEmpty else { return }

        let allCoins = try await coinRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
        let coinsToUpdate = allCoins.filter { identifiers.contains($0.identifier) }

        let updatedCoins = coinsToUpdate.map { $0.changing(state: state) }

        guard !updatedCoins.isEmpty else { return }

        try await coinStateRepository.saveOperation({ updatedCoins }, { [] }).asyncExecute()
    }
}
