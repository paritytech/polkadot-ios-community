import Foundation

enum ConnectionNodeSwitchCode {
    static let infura = -32_005
    static let alchemy = 429
    static let blustCapacity = -32_098
    static let blustRateLimit = -32_097

    static var allCodes: Set<Int> {
        [infura, alchemy, blustCapacity, blustRateLimit]
    }
}
