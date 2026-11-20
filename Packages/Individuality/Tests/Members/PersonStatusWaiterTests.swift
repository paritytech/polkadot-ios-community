import Foundation
import Testing
@testable import Individuality

struct PersonStatusWaiterTests {
    private let input = MembershipStatusInput(
        memberKey: Data(repeating: 2, count: 33),
        collection: Data(repeating: 1, count: 32)
    )

    @Test("waits for the person it was built for and returns once the member is included")
    func waitsForItsInput() async throws {
        let waiter = RecordingMembershipStatusWaiter(ringIndex: 3)

        try await PersonStatusWaiter(waiter: waiter, input: input).waitUntilIncluded()

        #expect(waiter.inputs.map(\.memberKey) == [input.memberKey])
        #expect(waiter.inputs.map(\.collection) == [input.collection])
    }

    @Test("a subscription that ends before inclusion fails the wait")
    func endedSubscriptionFails() async {
        let waiter = RecordingMembershipStatusWaiter(ringIndex: nil)

        await #expect(throws: MembershipStatusWaiterError.subscriptionEnded) {
            try await PersonStatusWaiter(waiter: waiter, input: input).waitUntilIncluded()
        }
    }
}

private final class RecordingMembershipStatusWaiter: MembershipStatusWaiting {
    private(set) var inputs: [MembershipStatusInput] = []
    private let ringIndex: MembersPallet.RingIndex?

    init(ringIndex: MembersPallet.RingIndex?) {
        self.ringIndex = ringIndex
    }

    func waitForStatus(of input: MembershipStatusInput) async throws -> MembersPallet.RingIndex {
        inputs.append(input)
        guard let ringIndex else { throw MembershipStatusWaiterError.subscriptionEnded }
        return ringIndex
    }

    func waitForStatus(of input: MembershipStatusInput, timeout _: Duration) async throws -> MembersPallet.RingIndex? {
        try await waitForStatus(of: input)
    }
}
