import Foundation
import SubstrateSdk
import Individuality
import UIKitExt

public protocol ProductsAccountManaging: Sendable {
    var isAllowanceSupported: Bool { get }

    func deriveAccount(_ productAccountId: ProductAccountId) throws -> AccountId

    func deriveAlias(_ productAccountId: ProductAccountId) throws -> ProductsAlias

    func requestResourceAllocation(
        for productId: ProductId,
        resources: [AllocatableResource],
        policy: OnExistingAllowancePolicy
    ) async throws -> [AllocationOutcome]

    @MainActor func setPresentationView(_ view: ControllerBackedProtocol)
}
