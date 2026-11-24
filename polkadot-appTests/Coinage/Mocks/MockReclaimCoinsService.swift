import Coinage
import Foundation

final class MockReclaimCoinsService: ReclaimCoinsServicing, @unchecked Sendable {
    struct Call: Equatable {
        let coinKeys: [Data]
        let groupId: CoinageTxGroupId
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    let failure: Error?

    init(failure: Error? = nil) {
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
}
