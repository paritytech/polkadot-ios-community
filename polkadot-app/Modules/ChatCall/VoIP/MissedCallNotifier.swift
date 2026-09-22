import Foundation

protocol MissedCallNotifying: Sendable {
    /// Tells the user why a call that CallKit already reported was ended without ringing.
    func notifyMissedCallWithoutPermissions() async
}

/// Posts the local notification that explains a call missed for lack of media permissions.
///
/// CallKit gives no way to surface a reason when a reported call is ended immediately, and
/// PushKit forbids skipping the report, so the explanation has to arrive out of band.
actor MissedCallNotifier {
    private let notificationService: UserNotificationServicing
    private let logger: LoggerProtocol

    init(
        notificationService: UserNotificationServicing = UserNotificationService.shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.notificationService = notificationService
        self.logger = logger
    }
}

extension MissedCallNotifier: MissedCallNotifying {
    func notifyMissedCallWithoutPermissions() async {
        do {
            try await notificationService.checkAccessAndScheduleNotificationNow(
                withIdentifier: UUID().uuidString,
                title: String(localized: .Notification.chatNotificationMissedCallNoPermissionsTitle),
                message: String(localized: .Notification.chatNotificationMissedCallNoPermissionsBody),
                source: .chat
            )
        } catch {
            logger.error("Could not post missed call notification: \(error.localizedDescription)")
        }
    }
}
