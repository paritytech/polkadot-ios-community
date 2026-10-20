import AsyncExtensions
import Coinage
import Foundation

/// Records reclaim requests and replays a scripted sequence of failed-reclaim sets for every subscription.
final class MockReclaimCoinsService: ReclaimCoinsServicing, @unchecked Sendable {
    struct Call: Equatable {
        let coinKeys: [Data]
        let groupId: CoinageTxGroupId
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    let failedReclaims: [Set<PublicKey>]
    let failure: Error?

    /// The default is one empty set: like the real subscription, it reports the current value first.
    init(failedReclaims: [Set<PublicKey>] = [[]], failure: Error? = nil) {
        self.failedReclaims = failedReclaims
        self.failure = failure
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func reclaim(coinKeys: [Data], groupId: CoinageTxGroupId) async throws {
        lock.lock()
        recordedCalls.append(Call(coinKeys: coinKeys, groupId: groupId))
        lock.unlock()

        if let failure {
            throw failure
        }
    }

    func subscribeFailedReclaims(groupId _: CoinageTxGroupId) -> AnyAsyncSequence<Set<PublicKey>> {
        let failedReclaims = failedReclaims

        return AsyncStream<Set<PublicKey>> { continuation in
            for failed in failedReclaims {
                continuation.yield(failed)
            }
            continuation.finish()
        }
        .eraseToAnyAsyncSequence()
    }
}
