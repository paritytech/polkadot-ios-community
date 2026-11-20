@testable import polkadot_app
import AsyncExtensions
import Foundation
import Individuality

/// A lite person that is already in its ring.
struct IncludedPersonStatusWaiter: PersonStatusWaiting {
    func waitUntilIncluded() async throws {}
}

/// Holds every wait until `include()`.
final class ScriptedPersonStatusWaiter: PersonStatusWaiting, @unchecked Sendable {
    private let included = AsyncCurrentValueSubject<Bool>(false)

    func include() {
        included.send(true)
    }

    func waitUntilIncluded() async throws {
        for try await isIncluded in included.eraseToAnyAsyncSequence() where isIncluded {
            return
        }
        throw MembershipStatusWaiterError.subscriptionEnded
    }
}
