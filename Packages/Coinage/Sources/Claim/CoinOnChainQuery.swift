import AsyncExtensions
import Foundation
import Operation_iOS
import StructuredConcurrency
import SubstrateSdk
import SubstrateStorageQuery
import SubstrateStorageSubscription
import SubstrateSdkExt
import Individuality

enum CoinOnChainQueryError: Error {
    case timeout
    case subscriptionTerminated
}

/// Batch-fetches on-chain coin state for given public keys.
protocol CoinOnChainQuerying: Sendable {
    /// Fetches on-chain coins for multiple public keys at a specific block hash.
    /// Returns an array of optionals in the same order as the input keys.
    func fetchCoins(for publicKeys: [Data], atBlockHash: Data?) async throws -> [CoinSyncResult.OnChainCoin?]

    /// Waits until all coins for the given public keys appear on-chain, or throws when the subscription terminates.
    func awaitAllCoinsOnChain(for publicKeys: [Data]) async throws

    /// Waits until all coins for the given public keys are absent/spent on-chain, or throws when the subscription
    /// terminates.
    func awaitAllCoinsOffChain(for publicKeys: [Data]) async throws
}

extension CoinOnChainQuerying {
    /// Fetches on-chain coins for multiple public keys in a single RPC call.
    /// Returns an array of optionals in the same order as the input keys.
    func fetchCoins(for publicKeys: [Data]) async throws -> [CoinSyncResult.OnChainCoin?] {
        try await fetchCoins(for: publicKeys, atBlockHash: nil)
    }
}

/// Default implementation that queries the Coinage pallet storage via RPC.
final class CoinOnChainQueryService: CoinOnChainQuerying, @unchecked Sendable {
    private let connection: any JSONRPCEngine
    private let runtimeService: any RuntimeCodingServiceProtocol
    private let storageRequestFactory: any StorageRequestFactoryProtocol

    init(
        connection: any JSONRPCEngine,
        runtimeService: any RuntimeCodingServiceProtocol,
        storageRequestFactory: any StorageRequestFactoryProtocol
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.storageRequestFactory = storageRequestFactory
    }

    func fetchCoins(for publicKeys: [Data], atBlockHash: Data?) async throws -> [CoinSyncResult.OnChainCoin?] {
        guard !publicKeys.isEmpty else { return [] }

        let coderFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()
        let coinPath = CoinagePallet.Storage.coinsByOwner

        let queryWrapper: CompoundOperationWrapper<[StorageResponse<CoinSyncResult.OnChainCoin>]> =
            storageRequestFactory.queryItems(
                engine: connection,
                keyParams: { publicKeys.map { BytesCodable(wrappedValue: $0) } },
                factory: { coderFactory },
                storagePath: coinPath(),
                options: StorageQueryListOptions(atBlock: atBlockHash)
            )

        let responses = try await queryWrapper.asyncExecute()
        return responses.map(\.value)
    }

    /// Subscribes to on-chain coin storage and resolves when all requested keys have a non-nil coin.
    ///
    /// Each emission may be a partial update (only keys changed in that block), so state is
    /// accumulated across emissions. Throws `subscriptionTerminated` if the stream ends before
    /// all keys are satisfied. Callers are responsible for racing this against a block-based timeout.
    func awaitAllCoinsOnChain(for publicKeys: [Data]) async throws {
        guard !publicKeys.isEmpty else { return }

        let mappingKeys = Set(publicKeys.map { $0.toHex() })

        let accumulatedStream = subscribeCoins(for: publicKeys)
            .scan([String: CoinSyncResult.OnChainCoin]()) { accumulated, result in
                var next = accumulated
                for (key, coin) in result.updates where coin != nil {
                    next[key] = coin
                }
                return next
            }

        for try await accumulated in accumulatedStream {
            guard mappingKeys.allSatisfy({ accumulated[$0] != nil }) else {
                continue
            }
            return
        }

        // Stream ended without satisfying all keys (e.g. websocket disconnect)
        throw CoinOnChainQueryError.subscriptionTerminated
    }

    /// Subscribes to on-chain coin storage and resolves when all requested keys have a nil coin (spent/absent).
    ///
    /// Accumulates state across partial emissions. Throws `subscriptionTerminated` if the stream
    /// ends before all keys are spent. Callers are responsible for racing against a block timeout.
    func awaitAllCoinsOffChain(for publicKeys: [Data]) async throws {
        guard !publicKeys.isEmpty else { return }

        let mappingKeys = Set(publicKeys.map { $0.toHex() })

        let accumulatedStream = subscribeCoins(for: publicKeys)
            .scan([String: CoinSyncResult.OnChainCoin]()) { accumulated, result in
                var next = accumulated
                for (key, coin) in result.updates {
                    if coin != nil {
                        next[key] = coin
                    } else {
                        next.removeValue(forKey: key)
                    }
                }
                return next
            }

        for try await accumulated in accumulatedStream {
            guard mappingKeys.allSatisfy({ accumulated[$0] == nil }) else {
                continue
            }
            return
        }

        throw CoinOnChainQueryError.subscriptionTerminated
    }

    /// Opens a Substrate storage subscription for `CoinsByOwner` entries keyed by public key.
    ///
    /// Uses the same `MapSubscriptionRequest` + `CallbackBatchStorageSubscription` pattern
    /// as `CoinStateSyncService.performSync()`. The returned stream emits `CoinSyncResult`
    /// on every block where any of the watched storage keys change.
    private func subscribeCoins(for publicKeys: [Data]) -> AnyAsyncSequence<CoinSyncResult> {
        let requests: [BatchStorageSubscriptionRequest] = publicKeys.map { publicKey in
            let mappingKey = publicKey.toHex()
            let storagePath = CoinagePallet.Storage.coinsByOwner
            let innerRequest = MapSubscriptionRequest(
                storagePath: storagePath(),
                localKey: "",
                keyParamClosure: { BytesCodable(wrappedValue: publicKey) }
            )
            return BatchStorageSubscriptionRequest(innerRequest: innerRequest, mappingKey: mappingKey)
        }

        return CallbackBatchStorageSubscription.asyncStream(
            requests: requests,
            connection: connection,
            runtimeService: runtimeService,
            logger: nil
        )
    }
}
