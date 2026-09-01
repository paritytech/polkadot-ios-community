import Foundation
import AsyncExtensions
import SubstrateStorageSubscription
import SubstrateSdk
import Operation_iOS
import SDKLogger

public extension CallbackBatchStorageSubscription {
    /// Subscribes to `requests` and streams each result.
    ///
    /// Transparently bounded by the node's `state_subscribeStorage` key limit: a request list longer
    /// than ``maxSubscriptionKeys`` is split into several subscriptions whose emissions are merged
    /// into one stream. Each emission is an independent partial keyed update, so a caller processes
    /// the merged stream exactly as it would a single subscription's — no cross-chunk snapshotting.
    static func asyncStream(
        requests: [BatchStorageSubscriptionRequest],
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        repository: AnyDataProviderRepository<ChainStorageItem>? = nil,
        logger: SDKLoggerProtocol?
    ) -> AnyAsyncSequence<T> {
        let chunks = stride(from: 0, to: requests.count, by: maxSubscriptionKeys).map { start in
            Array(requests[start ..< Swift.min(start + maxSubscriptionKeys, requests.count)])
        }

        guard chunks.count > 1 else {
            return asyncChunkStream(
                requests: requests,
                connection: connection,
                runtimeService: runtimeService,
                repository: repository,
                logger: logger
            )
        }

        return AsyncThrowingStream<T, Error> { continuation in
            let tasks = chunks.map { chunk in
                Task {
                    do {
                        let stream = asyncChunkStream(
                            requests: chunk,
                            connection: connection,
                            runtimeService: runtimeService,
                            repository: repository,
                            logger: logger
                        )
                        for try await value in stream {
                            continuation.yield(value)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
        }
        .eraseToAnyAsyncSequence()
    }

    /// The node's per-`state_subscribeStorage` key cap. Longer request lists are chunked to this size.
    private static var maxSubscriptionKeys: Int { 1000 }

    /// One subscription over `requests` (assumed within the node's key limit), as an async stream.
    private static func asyncChunkStream(
        requests: [BatchStorageSubscriptionRequest],
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        repository: AnyDataProviderRepository<ChainStorageItem>?,
        logger: SDKLoggerProtocol?
    ) -> AnyAsyncSequence<T> {
        let callbackQueue = DispatchQueue(label: "io.callback.storage.subscription")

        let stream = AsyncThrowingStream<T, Error> { continuation in
            let subscription = CallbackBatchStorageSubscription(
                requests: requests,
                connection: connection,
                runtimeService: runtimeService,
                repository: repository,
                operationQueue: OperationManagerFacade.sharedDefaultQueue,
                callbackQueue: callbackQueue
            ) { result in
                switch result {
                case let .success(value):
                    continuation.yield(value)
                case let .failure(error):
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                logger?.debug("Stream unsubscribed")
                subscription.unsubscribe()
            }

            subscription.subscribe()
        }

        return stream.eraseToAnyAsyncSequence()
    }
}
