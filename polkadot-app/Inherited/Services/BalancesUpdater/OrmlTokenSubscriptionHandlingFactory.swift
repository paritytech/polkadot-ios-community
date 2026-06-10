import Operation_iOS
import Foundation
import SubstrateStorageSubscription

final class OrmlTokenSubscriptionHandlingFactory: RemoteSubscriptionHandleFactoryProtocol {
    let factory: OrmlTokenSubscriptionFactoryProtocol

    init(
        factory: OrmlTokenSubscriptionFactoryProtocol
    ) {
        self.factory = factory
    }

    func createHandler(remoteStorageKey: Data, localStorageKey: String) -> StorageChildSubscribing {
        factory.createOrmlAccountSubscription(
            remoteStorageKey: remoteStorageKey,
            localStorageKey: localStorageKey
        )
    }
}
