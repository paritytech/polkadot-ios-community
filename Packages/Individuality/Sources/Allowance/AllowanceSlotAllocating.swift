import Foundation
import SubstrateSdk

public protocol AllowanceSlotAllocating {
    func assignSlot(accountId: AccountId) async throws
}

public enum AllowanceSlotAssignmentError: Error {
    case noSlotsAvailable
}
