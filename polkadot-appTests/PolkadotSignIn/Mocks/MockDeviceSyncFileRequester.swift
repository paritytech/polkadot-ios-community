@testable import polkadot_app
import Foundation

actor MockDeviceSyncFileRequester: DeviceSyncFileRequesting {
    private(set) var requests: [[DeviceSyncFileRequestItem]] = []
    private(set) var handledMessages: [Chat.DeviceSyncFileMessage] = []
    private(set) var didClose = false

    private let outcome: DeviceSyncFileRequestOutcome

    init(outcome: DeviceSyncFileRequestOutcome = .completed) {
        self.outcome = outcome
    }

    func request(_ items: [DeviceSyncFileRequestItem]) async -> [DeviceSyncFileRequestOutcome] {
        requests.append(items)
        return items.map { _ in outcome }
    }

    func handle(_ message: Chat.DeviceSyncFileMessage) async {
        handledMessages.append(message)
    }

    func close() async {
        didClose = true
    }
}
