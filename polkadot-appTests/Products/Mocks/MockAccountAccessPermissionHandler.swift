import Foundation
import Products

final class MockAccountAccessPermissionHandler: AccountAccessPermissionHandling, @unchecked Sendable {
    var granted = true
    private(set) var recordedProductIds: [String] = []
    private(set) var recordedTargetProductIds: [String] = []

    func request(productId: String, targetProductId: String) async throws -> Bool {
        recordedProductIds.append(productId)
        recordedTargetProductIds.append(targetProductId)
        return granted
    }
}
