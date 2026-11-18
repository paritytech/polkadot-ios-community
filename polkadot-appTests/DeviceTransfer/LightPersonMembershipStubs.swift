@testable import polkadot_app
import AsyncExtensions
import Foundation
import Individuality

/// A lite person that is already in its ring.
struct IncludedMembershipWaiter: MembershipStatusWaiting {
    func waitForStatus(of _: MembershipStatusInput) async throws -> MembersPallet.RingIndex { 0 }

    func waitForStatus(of _: MembershipStatusInput, timeout _: Duration) async throws -> MembersPallet.RingIndex? { 0 }
}

/// Holds every wait until `include()`.
final class ScriptedMembershipWaiter: MembershipStatusWaiting, @unchecked Sendable {
    private let included = AsyncCurrentValueSubject<Bool>(false)

    func include() {
        included.send(true)
    }

    func waitForStatus(of _: MembershipStatusInput) async throws -> MembersPallet.RingIndex {
        for try await isIncluded in included.eraseToAnyAsyncSequence() where isIncluded {
            return 0
        }
        throw MembershipStatusWaiterError.subscriptionEnded
    }

    func waitForStatus(of input: MembershipStatusInput, timeout _: Duration) async throws -> MembersPallet.RingIndex? {
        try await waitForStatus(of: input)
    }
}

extension LightPersonMembership {
    static let included = LightPersonMembership(waiter: IncludedMembershipWaiter(), input: .test)

    static func scripted(_ waiter: ScriptedMembershipWaiter) -> LightPersonMembership {
        LightPersonMembership(waiter: waiter, input: .test)
    }
}

extension MembershipStatusInput {
    static let test = MembershipStatusInput(
        memberKey: Data(repeating: 0x1E, count: 32),
        collection: PeopleLitePallet.membersIdentifier
    )
}
