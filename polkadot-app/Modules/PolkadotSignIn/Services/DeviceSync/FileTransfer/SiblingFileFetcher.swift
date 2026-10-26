import Foundation

protocol SiblingFileFetching: Sendable {
    /// Returns one outcome per item, in the same order. Without an open sibling channel every item is
    /// `notStored` right away.
    func fetch(_ items: [DeviceSyncFileRequestItem]) async -> [DeviceSyncFileRequestOutcome]
}

/// Fetches files from whichever sibling currently has an open `device-sync-file` channel.
final class SiblingFileFetcher: Sendable {
    static let maxFilesPerRequest = 64

    private let channels: any DeviceSyncFileChannelProviding

    init(channels: any DeviceSyncFileChannelProviding) {
        self.channels = channels
    }
}

extension SiblingFileFetcher: SiblingFileFetching {
    func fetch(_ items: [DeviceSyncFileRequestItem]) async -> [DeviceSyncFileRequestOutcome] {
        guard !items.isEmpty else { return [] }

        guard let requester = await channels.openRequester() else {
            return items.map { _ in .unavailable(.notStored) }
        }

        var outcomes: [DeviceSyncFileRequestOutcome] = []
        outcomes.reserveCapacity(items.count)

        for batchStart in stride(from: 0, to: items.count, by: Self.maxFilesPerRequest) {
            let batchEnd = min(batchStart + Self.maxFilesPerRequest, items.count)
            outcomes += await requester.request(Array(items[batchStart ..< batchEnd]))
        }

        return outcomes
    }
}
