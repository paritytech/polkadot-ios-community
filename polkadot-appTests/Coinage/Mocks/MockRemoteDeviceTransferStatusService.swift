import AsyncExtensions
import Coinage
import Foundation

final class MockRemoteDeviceTransferStatusService: RemoteDeviceTransferStatusServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCoinKeys: [[Data]] = []

    let snapshots: [[PublicKey: RemoteDeviceTransferCoinState]]

    init(snapshots: [[PublicKey: RemoteDeviceTransferCoinState]]) {
        self.snapshots = snapshots
    }

    var subscriptions: [[Data]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCoinKeys
    }

    func subscribeStatuses(coinKeys: [Data]) -> AnyAsyncSequence<[PublicKey: RemoteDeviceTransferCoinState]> {
        lock.lock()
        recordedCoinKeys.append(coinKeys)
        lock.unlock()

        let snapshots = snapshots

        return AsyncThrowingStream<[PublicKey: RemoteDeviceTransferCoinState], Error> { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
        .eraseToAnyAsyncSequence()
    }
}
