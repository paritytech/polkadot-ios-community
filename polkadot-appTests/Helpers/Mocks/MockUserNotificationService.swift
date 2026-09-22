@testable import polkadot_app
import Foundation
import UserNotifications

/// Records scheduled notifications instead of posting them, and can simulate a user who
/// has denied notification access.
final class MockUserNotificationService: UserNotificationServicing, @unchecked Sendable {
    struct Scheduled {
        let identifier: String
        let content: UNNotificationContent
        let timeInterval: TimeInterval
    }

    private let lock = NSLock()
    private var storage: [Scheduled] = []

    var accessStatus: NotificationAccessStatus

    var scheduled: [Scheduled] {
        lock.withLock { storage }
    }

    init(accessStatus: NotificationAccessStatus = .allowed) {
        self.accessStatus = accessStatus
    }

    func notificationAccessStatus() async -> NotificationAccessStatus {
        accessStatus
    }

    func requestNotificationsAuthorization(completion: ((Bool) -> Void)?) {
        completion?(accessStatus == .allowed)
    }

    func scheduleNotification(
        withIdentifier identifier: String,
        content: UNNotificationContent,
        after timeInterval: TimeInterval,
        completion: ((Error?) -> Void)?
    ) {
        lock.withLock {
            storage.append(.init(identifier: identifier, content: content, timeInterval: timeInterval))
        }

        completion?(nil)
    }

    func cancelScheduledNotifications(withIdentifiers _: [String]) {}

    func isNotificationScheduled(withIdentifier _: String, completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    func deliveredNotifications() async -> [UNNotification] { [] }

    func removeDeliveredNotifications(withIdentifiers _: [String]) {}

    func setBadge(_: Int) async {}
}
