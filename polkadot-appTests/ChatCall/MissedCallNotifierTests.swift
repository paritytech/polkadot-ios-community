@testable import polkadot_app
import Foundation
import Testing

struct MissedCallNotifierTests {
    @Test("Posts the missed call notification immediately")
    func postsNotification() async throws {
        let notificationService = MockUserNotificationService()
        let sut = MissedCallNotifier(notificationService: notificationService, logger: StubLogger())

        await sut.notifyMissedCallWithoutPermissions()

        #expect(notificationService.scheduled.count == 1)

        let scheduled = try #require(notificationService.scheduled.first)
        let expectedTitle = String(localized: .Notification.chatNotificationMissedCallNoPermissionsTitle)
        let expectedBody = String(localized: .Notification.chatNotificationMissedCallNoPermissionsBody)

        #expect(scheduled.timeInterval == 0)
        #expect(scheduled.content.title == expectedTitle)
        #expect(scheduled.content.body == expectedBody)
        #expect(
            scheduled.content.userInfo[PushNotificationKeys.pushSource] as? Int
                == PushNotificationSource.chat.rawValue
        )
    }

    /// The call has already been ended by the time this runs, so a denied notification
    /// permission must not surface as an unhandled error.
    @Test("Swallows the failure when notifications are not authorized")
    func toleratesDeniedNotifications() async {
        let notificationService = MockUserNotificationService(accessStatus: .notAllowed(denied: true))
        let sut = MissedCallNotifier(notificationService: notificationService, logger: StubLogger())

        await sut.notifyMissedCallWithoutPermissions()

        #expect(notificationService.scheduled.isEmpty)
    }
}
