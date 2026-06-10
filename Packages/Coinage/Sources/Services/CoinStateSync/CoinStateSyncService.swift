import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import StructuredConcurrency
import SDKLogger
import AsyncExtensions
import CommonService
import KeyDerivation

/// A service that monitors local coins and synchronizes their on-chain state.
public final class CoinStateSyncService: BaseSyncService {
    private let coinService: CoinServiceProtocol
    private let coinProvider: StreamableProvider<Coin>
    private let coinKeyDeriver: any CoinKeyDeriving
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol

    private var localCoinsMonitoringTask: Task<Void, Error>?
    private var syncTask: Task<Void, Error>?

    public init(
        coinService: CoinServiceProtocol,
        coinProvider: StreamableProvider<Coin>,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        entropyManager: any RootEntropyManaging,
        logger: any SDKLoggerProtocol
    ) {
        self.coinService = coinService
        self.coinProvider = coinProvider
        self.connection = connection
        self.runtimeService = runtimeService
        coinKeyDeriver = CoinKeypairFactory(entropyManager: entropyManager)
        super.init(logger: logger)
    }

    deinit {
        stopSyncUp()
    }

    /// Begins monitoring the local database for coins that require on-chain status updates.
    /// It filters for coins that are not spent.
    override public func performSyncUp() {
        localCoinsMonitoringTask = Task { [weak self] in
            guard let self else { return }

            let stream = coinProvider.asyncStream()
                .scan([String: Coin]()) { dict, changes in
                    changes.mergeToDict(dict)
                }
                .map(\.values)
                .map { $0.filter { $0.state != .spent && $0.age == nil } }

            for try await coins in stream {
                guard !coins.isEmpty else {
                    logger.debug("Coin sync stopped")
                    syncTask?.cancel()
                    continue
                }
                try Task.checkCancellation()

                do {
                    logger.debug("Coin sync started")
                    try await performSync(coins)
                } catch {
                    logger.error("Coin sync failed during monitoring: \(error)")
                }
            }
        }
    }

    override public func stopSyncUp() {
        localCoinsMonitoringTask?.cancel()
        syncTask?.cancel()
    }
}

extension CoinStateSyncService {
    /// Orchestrates the on-chain subscription for a set of coins.
    /// Cancels existing subscriptions and creates a new batch request.
    private func performSync(_ coins: [Coin]) async throws {
        syncTask?.cancel()

        let requests: [BatchStorageSubscriptionRequest] = try coins.map { coin in
            let publicKey = try self.coinKeyDeriver.derivePublicKey(for: coin)
            let mappingKey = publicKey.toHex()
            let storagePath = CoinagePallet.Storage.coinsByOwner
            let innerRequest = MapSubscriptionRequest(
                storagePath: storagePath(),
                localKey: "",
                keyParamClosure: { BytesCodable(wrappedValue: publicKey) }
            )
            return BatchStorageSubscriptionRequest(innerRequest: innerRequest, mappingKey: mappingKey)
        }

        guard !requests.isEmpty else { return }

        syncTask = Task { [weak self] in
            guard let self else { return }

            let stream: AnyAsyncSequence<CoinSyncResult> = CallbackBatchStorageSubscription
                .asyncStream(
                    requests: requests,
                    connection: connection,
                    runtimeService: runtimeService,
                    logger: logger
                )

            for try await result in stream {
                try Task.checkCancellation()
                try await handleSubscriptionUpdate(result)
            }
        }
    }

    private func handleSubscriptionUpdate(_ result: CoinSyncResult) async throws {
        let availableCoins = try await coinService.fetchAllCoins()
        guard !availableCoins.isEmpty else { return }

        var coinMap: [String: Coin] = [:]
        for coin in availableCoins where coin.state != .spent {
            guard let pubKey = try? coinKeyDeriver.derivePublicKey(for: coin) else {
                continue
            }
            coinMap[pubKey.toHex()] = coin
        }

        var coinsToUpdate: [Coin] = []

        for (mappingKey, onChainCoin) in result.updates {
            guard let coin = coinMap[mappingKey] else { continue }

            if let onChainCoin {
                // Present on chain -> Update local age
                let onChainAge = onChainCoin.age
                guard coin.age != onChainAge else { continue }
                coinsToUpdate.append(coin.changing(age: onChainAge))
            } else {
                // Not present on chain
                guard coin.age != nil else { continue }
                // Local has age + not present on chain -> Mark coin as SPENT
                coinsToUpdate.append(coin.changing(state: .spent))
            }
        }

        guard !coinsToUpdate.isEmpty else { return }
        try await coinService.save(coins: coinsToUpdate)
        logger.debug("Updated \(coinsToUpdate.count) coins via sync subscription")
    }
}
