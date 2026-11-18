import Foundation
import Individuality

/// The lite person this seed registers as. Its ring inclusion is what lets the identity account take a
/// statement-store slot, so a record submitted before it only collects `noAllowance` rejections.
struct LightPersonMembership: @unchecked Sendable {
    let waiter: any MembershipStatusWaiting
    let input: MembershipStatusInput

    func waitUntilIncluded() async throws {
        _ = try await waiter.waitForStatus(of: input)
    }
}
