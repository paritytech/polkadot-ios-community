import Foundation
import Operation_iOS
import SubstrateStorageSubscription

final class EmptyHandlingStorageSubscription: StorageChildSubscribing {
    let remoteStorageKey: Data
    let logger: LoggerProtocol

    init(remoteStorageKey: Data, logger: LoggerProtocol) {
        self.remoteStorageKey = remoteStorageKey
        self.logger = logger
    }

    func processUpdate(_: Data?, blockHash _: Data?) {
        logger.warning("Empty handler for key: \(remoteStorageKey.toHex())")
    }
}
