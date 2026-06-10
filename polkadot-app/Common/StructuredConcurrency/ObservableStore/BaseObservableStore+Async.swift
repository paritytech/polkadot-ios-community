import Foundation
import CommonService
import AsyncExtensions

extension BaseObservableStateStoreProtocol {
    func observe() -> AnyAsyncSequence<RemoteState?> {
        let syncQueue = DispatchQueue(label: "io.observable.store.async.updates")
        let observer = NSObject()

        return AsyncThrowingStream { continuation in
            add(
                observer: observer,
                sendStateOnSubscription: true,
                queue: syncQueue
            ) { _, newState in
                continuation.yield(newState)
            }

            continuation.onTermination = { @Sendable _ in
                remove(observer: observer)
            }
        }
        .eraseToAnyAsyncSequence()
    }
}
