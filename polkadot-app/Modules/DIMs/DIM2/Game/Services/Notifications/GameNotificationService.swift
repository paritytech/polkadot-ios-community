import Foundation
import Keystore_iOS
import UserNotifications
import Individuality

protocol GameNotificationServicing {
    var localNotificationService: UserNotificationServicing { get }

    func scheduleGameStartNotifications(for gameInfo: GameInfo?)
    func scheduleRegistrationStartNotifications(for schedule: GameSchedule?, currentGameInfo: GameInfo?)
}

class GameNotificationService {
    let localNotificationService: UserNotificationServicing
    private let gameStartReminder: any GameStartReminderServicing
    private let settingsManager: SettingsManagerProtocol
    private let logger: LoggerProtocol
    private let workQueue = DispatchQueue(label: "GameNotificationService.workQueue")

    init(
        localNotificationService: UserNotificationServicing,
        gameStartReminder: any GameStartReminderServicing,
        settingsManager: SettingsManagerProtocol = SettingsManager.shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.localNotificationService = localNotificationService
        self.gameStartReminder = gameStartReminder
        self.settingsManager = settingsManager
        self.logger = logger
    }
}

extension GameNotificationService: GameNotificationServicing {
    func scheduleGameStartNotifications(for gameInfo: GameInfo?) {
        switch gameInfo?.state {
        case .processing,
             .cancelling:
            cleanupWaitingRoomNotification()
        default:
            localNotificationService.notificationAccessStatus { [weak self] status in
                guard status.accessGranted else {
                    return
                }
                self?.workQueue.async {
                    self?.performScheduleWaitingRoomNotifications(for: gameInfo)
                }
            }
        }

        // Scheduling game
        guard
            let gameDate = gameInfo?.gameDate,
            let gameIndex = gameInfo?.index,
            gameInfo?.isRegistered == true
        else {
            gameStartReminder.cancelReminder()
            return
        }
        gameStartReminder.scheduleReminder(
            gameDate: gameDate,
            gameIndex: gameIndex,
            timingSeconds: settingsManager.gameAlarmTimingSeconds
        )
    }

    func scheduleRegistrationStartNotifications(for schedule: GameSchedule?, currentGameInfo: GameInfo?) {
        localNotificationService.notificationAccessStatus { [weak self] status in
            guard status.accessGranted else {
                return
            }

            self?.workQueue.async {
                self?.performScheduleRegistrationStartNotifications(
                    for: schedule,
                    currentGameInfo: currentGameInfo
                )
            }
        }
    }

    func cleanupWaitingRoomNotification() {
        workQueue.async { [weak self] in
            self?.cleanupNotification(for: Identifiers.waitingRoom, settingsKey: .waitingRoomNotificationDate)
        }
    }
}

private extension GameNotificationService {
    enum Identifiers {
        static let waitingRoom = "game_waiting_room"
        static let registrationStart = "registration_start"
    }

    enum TimeOffsets {
        static let waitingRoomMinutes = 1
        static let waitingRoomSeconds = 60 * waitingRoomMinutes
        static let registrationStartMinutes = 5
        static let registrationStartSeconds = 60 * registrationStartMinutes
    }

    struct GameStartNotificationInput {
        let identifier: String
        let gameIndex: GamePallet.GameIndex?
        let timeOffset: Int
        let storedSetting: SettingsKey
        let gameDate: Date?
        let isRegistered: Bool
        let title: String
        let body: String
        let sound: UNNotificationSound
    }

    struct RegistrationStartNotificationInput: Hashable {
        let notificationDate: Int
        let gameStartDate: Date
    }

    func performScheduleWaitingRoomNotifications(for gameInfo: GameInfo?) {
        performScheduleGameStartNotification(with: .init(
            identifier: Identifiers.waitingRoom,
            gameIndex: gameInfo?.index,
            timeOffset: TimeOffsets.waitingRoomSeconds,
            storedSetting: .waitingRoomNotificationDate,
            gameDate: gameInfo?.gameDate,
            isRegistered: gameInfo?.isRegistered == true,
            title: String(localized: .Notification.gameNotificationWaitingRoomTitle),
            body: String(localized: .Notification.gameNotificationWaitingRoomBody),
            sound: .default
        ))
    }

    func cleanupNotification(for identifier: String, settingsKey: SettingsKey) {
        localNotificationService.cancelScheduledNotifications(
            withIdentifiers: [identifier]
        )
        localNotificationService.removeDeliveredNotifications(
            withIdentifiers: [identifier]
        )
        settingsManager.removeValue(for: settingsKey)
    }

    func performScheduleGameStartNotification(with input: GameStartNotificationInput) {
        let notificationDate: Int?

        if let gameDate = input.gameDate, input.isRegistered {
            let intervalSinceReferenceDate = Int(gameDate.timeIntervalSinceReferenceDate)
            notificationDate = intervalSinceReferenceDate - input.timeOffset
        } else {
            notificationDate = nil
        }

        let storedDate = settingsManager.integer(for: input.storedSetting)
        let isChanged = notificationDate != storedDate

        logger.debug("\(input.identifier) isChanged = \(isChanged)")

        guard isChanged else {
            return
        }

        cleanupNotification(for: input.identifier, settingsKey: input.storedSetting)

        guard let notificationDate else {
            return
        }

        let date = Date(timeIntervalSinceReferenceDate: TimeInterval(notificationDate))
        let now = Date()

        guard date > now else {
            return
        }

        settingsManager.set(
            value: notificationDate,
            for: input.storedSetting
        )

        var notificationUserInfo: [String: Any] = [
            PushNotificationKeys.chatExtensionId: DIM2ChatExtension.identifier,
            PushNotificationKeys.pushSource: PushNotificationSource.chat.rawValue
        ]

        if input.identifier == Identifiers.waitingRoom {
            notificationUserInfo[PushNotificationKeys.gameState] = PushGameNotificationType.waitingRoom.rawValue
        }

        if let gameIndex = input.gameIndex {
            notificationUserInfo[PushNotificationKeys.gameIndex] = Int(gameIndex)
        }

        localNotificationService.scheduleNotification(
            withIdentifier: input.identifier,
            content: makeContent(
                title: input.title,
                body: input.body,
                sound: input.sound,
                userInfo: notificationUserInfo
            ),
            after: date.timeIntervalSince(now)
        ) { [weak self] error in
            self?.logger.debug("\(input.identifier) scheduled with error: \(String(describing: error))")
        }
    }

    func performScheduleRegistrationStartNotifications(
        for schedule: GameSchedule?,
        currentGameInfo: GameInfo?
    ) {
        let notificationInputs = makeRegistrationStartInputs(
            schedule: schedule,
            currentGameInfo: currentGameInfo
        )
        let notificationDates = notificationInputs.map(\.notificationDate)
        let storedDates = settingsManager.integerArray(for: .registrationStartNotificationDates)
        let isChanged = notificationDates != (storedDates ?? [])

        logger.debug("isChanged = \(isChanged)")

        guard isChanged else {
            return
        }

        let notificationIdentifiers = makeRegistrationStartIdentifiers(dates: notificationDates)
        let storedIdentifiers = makeRegistrationStartIdentifiers(dates: storedDates ?? [])

        if !storedIdentifiers.isEmpty {
            localNotificationService.cancelScheduledNotifications(withIdentifiers: storedIdentifiers)
            settingsManager.removeValue(for: .registrationStartNotificationDates)
        }

        guard !notificationIdentifiers.isEmpty else {
            return
        }

        settingsManager.set(intArray: notificationDates, for: .registrationStartNotificationDates)

        let now = Date()

        for (index, identifier) in notificationIdentifiers.enumerated() {
            let notificationInput = notificationInputs[index]
            let date = Date(timeIntervalSinceReferenceDate: TimeInterval(notificationInput.notificationDate))
            let delay = date.timeIntervalSince(now)

            guard date > now else {
                continue
            }

            let monthText = DateFormatter.fullMonth.value(for: .current)
                .string(from: notificationInput.gameStartDate)

            let content = makeContent(
                title: String(localized: .Notification.gameNotificationRegistrationStartTitle(monthText)),
                body: String(
                    localized: .Notification
                        .gameNotificationRegistrationStartBody(TimeOffsets.registrationStartMinutes)
                ),
                sound: .default,
                userInfo: [
                    PushNotificationKeys.chatExtensionId: DIM2ChatExtension.identifier,
                    PushNotificationKeys.pushSource: PushNotificationSource.chat.rawValue,
                    PushNotificationKeys.gameState: PushGameNotificationType.register.rawValue
                ]
            )

            localNotificationService.scheduleNotification(
                withIdentifier: identifier,
                content: content,
                after: delay
            ) { [weak self] error in
                self?.logger.debug("\(identifier) scheduled with error: \(String(describing: error))")
            }
        }
    }

    func makeRegistrationStartIdentifiers(dates: [Int]) -> [String] {
        dates.map { "\(Identifiers.registrationStart)_\($0)" }
    }

    func makeRegistrationStartInputs(
        schedule: GameSchedule?,
        currentGameInfo: GameInfo?
    ) -> [RegistrationStartNotificationInput] {
        let scheduledInputs = schedule?.items.map {
            makeRegistrationStartInput(gameStartDate: $0.gameStartDate)
        } ?? []

        let currentGameInput = makeCurrentGameRegistrationStartInput(currentGameInfo)

        return Dictionary(
            grouping: scheduledInputs + [currentGameInput].compactMap { $0 },
            by: \.notificationDate
        )
        .values
        .compactMap(\.first)
        .sorted { $0.notificationDate < $1.notificationDate }
    }

    func makeCurrentGameRegistrationStartInput(_ gameInfo: GameInfo?) -> RegistrationStartNotificationInput? {
        guard
            let gameInfo,
            case .registration = gameInfo.state,
            !gameInfo.isRegistered,
            let gameDate = gameInfo.gameDate
        else {
            return nil
        }

        return makeRegistrationStartInput(gameStartDate: gameDate)
    }

    func makeRegistrationStartInput(gameStartDate: Date) -> RegistrationStartNotificationInput {
        .init(
            notificationDate: Int(gameStartDate.timeIntervalSinceReferenceDate) -
                TimeOffsets.registrationStartSeconds,
            gameStartDate: gameStartDate
        )
    }

    func makeContent(
        title: String,
        body: String,
        sound: UNNotificationSound,
        userInfo: [AnyHashable: Any]
    ) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.userInfo = userInfo

        return content
    }
}
