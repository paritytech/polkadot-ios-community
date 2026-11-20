import Foundation

public protocol PersonStatusWaiting: Sendable {
    /// Returns once the person is an included member whose key the ring root covers, or throws when the
    /// subscription ends first.
    func waitUntilIncluded() async throws
}

/// One person's membership over a `MembershipStatusWaiting`.
public struct PersonStatusWaiter: PersonStatusWaiting, @unchecked Sendable {
    private let waiter: any MembershipStatusWaiting
    private let input: MembershipStatusInput

    public init(waiter: any MembershipStatusWaiting, input: MembershipStatusInput) {
        self.waiter = waiter
        self.input = input
    }

    public func waitUntilIncluded() async throws {
        _ = try await waiter.waitForStatus(of: input)
    }
}
