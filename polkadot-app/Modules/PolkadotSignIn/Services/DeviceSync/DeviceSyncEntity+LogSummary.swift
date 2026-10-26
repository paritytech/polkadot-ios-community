import Foundation

extension [Chat.DeviceSyncEntity] {
    var syncLogSummary: String {
        map { "\($0.logLabel):\($0.itemCount)" }.joined(separator: ";")
    }
}

extension Chat.DeviceSyncEntity {
    var itemCount: Int {
        switch self {
        case let .devices(items): items.count
        case let .chatsAdded(items): items.count
        case let .chatsRemoved(items): items.count
        case let .messages(items): items.count
        case let .chatsBlocked(items): items.count
        case let .incomingRequestsAdded(items): items.count
        case let .incomingRequestsStatusUpdated(items): items.count
        case let .outgoingRequestsAdded(items): items.count
        case let .outgoingRequestsStatusUpdated(items): items.count
        case let .coinsHandedOff(items): items.count
        case let .coinageMessagesStatusUpdated(items): items.count
        }
    }
}
