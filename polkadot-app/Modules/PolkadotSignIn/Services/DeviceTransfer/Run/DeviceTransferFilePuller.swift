import Algorithms
import Foundation
import os

struct DeviceTransferFileProgress: Equatable {
    let receivedBytes: UInt64
    let totalBytes: UInt64
}

protocol DeviceTransferFilePulling {
    func pullMissingFiles(onProgress: @escaping @Sendable (DeviceTransferFileProgress) -> Void) async throws
}

final class DeviceTransferFilePuller {
    private let scanner: DeviceTransferMissingFileScanning
    private let requester: any DeviceSyncFileRequesting
    private let batchSize: Int
    private let logger: LoggerProtocol

    init(
        scanner: DeviceTransferMissingFileScanning,
        requester: any DeviceSyncFileRequesting,
        batchSize: Int = SiblingFileFetcher.maxFilesPerRequest,
        logger: LoggerProtocol
    ) {
        self.scanner = scanner
        self.requester = requester
        self.batchSize = batchSize
        self.logger = logger
    }
}

extension DeviceTransferFilePuller: DeviceTransferFilePulling {
    func pullMissingFiles(onProgress: @escaping @Sendable (DeviceTransferFileProgress) -> Void) async throws {
        let available = try await availableFiles()
        let totalBytes = available.reduce(0) { $0 + $1.size }
        let receivedBytes = OSAllocatedUnfairLock<UInt64>(initialState: 0)

        onProgress(DeviceTransferFileProgress(receivedBytes: 0, totalBytes: totalBytes))

        let outcomes = await pull(available.map(\.item)) { bytes in
            let received = receivedBytes.withLock { total in
                total += bytes
                return total
            }
            onProgress(DeviceTransferFileProgress(receivedBytes: min(received, totalBytes), totalBytes: totalBytes))
        }

        let completed = outcomes.filter { $0 == .completed }.count
        logger.debug("Device transfer pulled \(completed) of \(available.count) available file(s)")
    }
}

private extension DeviceTransferFilePuller {
    func availableFiles() async throws -> [(item: DeviceSyncFileRequestItem, size: UInt64)] {
        let missing = try await scanner.missingFiles()
        var available: [(item: DeviceSyncFileRequestItem, size: UInt64)] = []

        for batch in missing.chunks(ofCount: batchSize) {
            let availability = await requester.requestAvailability(batch.map(\.file))

            for (item, entry) in zip(batch, availability) {
                if case let .available(totalSize) = entry {
                    available.append((item, totalSize))
                }
            }
        }

        logger.debug("Device transfer found \(available.count) of \(missing.count) missing file(s) on the old phone")
        return available
    }

    func pull(
        _ items: [DeviceSyncFileRequestItem],
        onBytes: @escaping DeviceSyncFileBytesHandler
    ) async -> [DeviceSyncFileRequestOutcome] {
        var outcomes: [DeviceSyncFileRequestOutcome] = []

        for batch in items.chunks(ofCount: batchSize) {
            outcomes += await requester.request(Array(batch), onBytes: onBytes)
        }

        return outcomes
    }
}
