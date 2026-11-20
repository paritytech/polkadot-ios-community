import Foundation

public protocol PersonStatusWaiting: Sendable {
    /// Returns once the ring root covers the person's key.
    func waitUntilIncluded() async throws
}

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
