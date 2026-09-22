import Foundation
import Products

final class MockOSPermissionAsker: OSPermissionAsking, @unchecked Sendable {
    var checkResult: OSPermissionStatus = .notDetermined
    var requestResult: Bool = true

    private(set) var checkedCapabilities: [DeviceCapabilityType] = []

    func checkPermission(for capability: DeviceCapabilityType) async -> OSPermissionStatus {
        checkedCapabilities.append(capability)
        return checkResult
    }

    func requestPermission(for _: DeviceCapabilityType) async -> Bool {
        requestResult
    }
}
