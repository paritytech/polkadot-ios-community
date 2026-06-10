import Foundation
import Individuality
import SubstrateSdk

final class MockAllowanceManager: AllowanceManaging {
    var allocateCallCount = 0
    var allocateError: Error?

    func allocate(
        accountId _: AccountId,
        policy _: OnExistingAllowancePolicy
    ) async throws {
        allocateCallCount += 1

        if let allocateError {
            throw allocateError
        }
    }
}
