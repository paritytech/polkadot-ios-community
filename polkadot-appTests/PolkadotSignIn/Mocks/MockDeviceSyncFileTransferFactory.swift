@testable import polkadot_app
import Foundation

final class MockDeviceSyncFileTransferFactory: DeviceSyncFileTransferMaking, @unchecked Sendable {
    enum Event: Equatable {
        case started(Int)
        case closed(Int)
    }

    let events = DeviceSyncTestEventRecorder<Event>()

    private let lock = NSLock()
    private var madeCount = 0

    func makeTransfer(
        flow _: any DeviceSyncPeerConnectionFlowing,
        peerLogger _: LoggerProtocol
    ) -> any DeviceSyncFileTransferring {
        let index = lock.withLock {
            madeCount += 1
            return madeCount
        }
        return MockDeviceSyncFileTransfer(index: index, events: events)
    }
}

private actor MockDeviceSyncFileTransfer: DeviceSyncFileTransferring {
    private let index: Int
    private let events: DeviceSyncTestEventRecorder<MockDeviceSyncFileTransferFactory.Event>

    init(index: Int, events: DeviceSyncTestEventRecorder<MockDeviceSyncFileTransferFactory.Event>) {
        self.index = index
        self.events = events
    }

    func start() async {
        events.record(.started(index))
    }

    func close() async {
        events.record(.closed(index))
    }
}
