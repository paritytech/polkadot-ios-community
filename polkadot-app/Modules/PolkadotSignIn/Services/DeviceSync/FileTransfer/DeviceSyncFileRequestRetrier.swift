import Foundation

/// Re-requests files whose bytes failed the digest check; a still-mismatching file keeps `.hashMismatch`.
struct DeviceSyncFileRequestRetrier: Sendable {
    static let defaultExtraAttempts = 2

    let extraAttempts: Int

    init(extraAttempts: Int = DeviceSyncFileRequestRetrier.defaultExtraAttempts) {
        self.extraAttempts = extraAttempts
    }

    func request(
        _ items: [DeviceSyncFileRequestItem],
        using requester: any DeviceSyncFileRequesting,
        onBytes: @escaping DeviceSyncFileBytesHandler
    ) async -> [DeviceSyncFileRequestOutcome] {
        var outcomes = await requester.request(items, onBytes: onBytes)

        for _ in 0 ..< extraAttempts {
            let mismatched = outcomes.indices.filter { outcomes[$0] == .hashMismatch }

            guard !mismatched.isEmpty else { break }

            let retried = await requester.request(mismatched.map { items[$0] }, onBytes: onBytes)

            for (index, outcome) in zip(mismatched, retried) {
                outcomes[index] = outcome
            }
        }

        return outcomes
    }
}
