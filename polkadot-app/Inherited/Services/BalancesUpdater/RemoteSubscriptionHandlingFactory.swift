import Foundation
import Operation_iOS
import SubstrateStorageSubscription

protocol RemoteSubscriptionHandleFactoryProtocol {
    func createHandler(remoteStorageKey: Data, localStorageKey: String) -> StorageChildSubscribing
}
