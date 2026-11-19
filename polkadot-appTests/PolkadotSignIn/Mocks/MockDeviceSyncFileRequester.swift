@testable import polkadot_app
import Foundation

actor MockDeviceSyncFileRequester: DeviceSyncFileRequesting {
    private(set) var requests: [[DeviceSyncFileRequestItem]] = []
    private(set) var handledMessages: [Chat.DeviceSyncFileMessage] = []
    private(set) var didClose = false

    private let outcome: DeviceSyncFileRequestOutcome
    private var scriptedOutcomes: [[DeviceSyncFileRequestOutcome]]

    /// Each request consumes the next scripted list, positionally; missing entries and later requests get `outcome`.
    init(
        outcome: DeviceSyncFileRequestOutcome = .completed,
        scriptedOutcomes: [[DeviceSyncFileRequestOutcome]] = []
    ) {
        self.outcome = outcome
        self.scriptedOutcomes = scriptedOutcomes
    }

    func request(
        _ items: [DeviceSyncFileRequestItem],
        onBytes _: @escaping DeviceSyncFileBytesHandler
    ) async -> [DeviceSyncFileRequestOutcome] {
        requests.append(items)
        let script = scriptedOutcomes.isEmpty ? [] : scriptedOutcomes.removeFirst()
        return items.indices.map { script.indices.contains($0) ? script[$0] : outcome }
    }

    func requestAvailability(
        _ files: [Chat.DeviceSyncFileMessage.FileReference]
    ) async -> [Chat.DeviceSyncFileMessage.Availability] {
        files.map { _ in .unavailable(.notStored) }
    }

    func handle(_ message: Chat.DeviceSyncFileMessage) async {
        handledMessages.append(message)
    }

    func close() async {
        didClose = true
    }
}
