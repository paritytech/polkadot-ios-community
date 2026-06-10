import Foundation
import AsyncExtensions
import SubstrateStorageSubscription
import SubstrateSdk
import Operation_iOS
import SDKLogger

public extension CallbackBatchStorageSubscription {
    static func asyncStream(
        requests: [BatchStorageSubscriptionRequest],
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        repository: AnyDataProviderRepository<ChainStorageItem>? = nil,
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
