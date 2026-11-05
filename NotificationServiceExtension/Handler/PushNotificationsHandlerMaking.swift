import Foundation
import Foundation_iOS
import Operation_iOS
import MessageExchangeKit

protocol PushNotificationHandling {
    func handle(
        completion: @escaping (NotificationContentResult) -> Void
    )
}

protocol PushNotificationHandlerMaking {
    func createHandler(message: NotificationMessage) -> PushNotificationHandling
}

final class PushNotificationHandlerFactory: PushNotificationHandlerMaking {
    let messageDecoder: ChatPushMessageCoding
    let storage: any StorageFacadeProtocol
    let installationStatusStore: InstallationStatusStoring

    init(
        messageDecoder: ChatPushMessageCoding,
        storage: any StorageFacadeProtocol,
        installationStatusStore: InstallationStatusStoring
    ) {
        self.messageDecoder = messageDecoder
        self.storage = storage
        self.installationStatusStore = installationStatusStore
    }

    func createHandler(message: NotificationMessage) -> PushNotificationHandling {
        guard !installationStatusStore.isReplaced else {
            return ReplacedInstallationHandler()
        }

        switch message {
        case let .newMessage(pushId, text):
            let messageRepository = storage.createRepository(
                filter: nil,
                sortDescriptors: [],
                mapper: AnyCoreDataMapper(PushNotificationChatMessageEntityMapper())
            )

            return NewMessageHandler(
                pushId: pushId,
                messageHex: text,
                contactsService: ContactsLocalStorageService(),
                messageDecoder: messageDecoder,
                messageRepository: AnyDataProviderRepository(messageRepository),
                unreadMessageCountService: UnreadMessageCountService()
            )
        }
    }
}

/// A replaced phone still holds the shared device key, so it could read messages meant for the active one.
struct ReplacedInstallationHandler: PushNotificationHandling {
    func handle(completion: @escaping (NotificationContentResult) -> Void) {
        completion(.createBestAttemptResult())
    }
}

private extension InstallationStatusStoring {
    /// Nothing saved yet, as after an update, keeps notifications as they were.
    var isReplaced: Bool {
        switch status {
        case .inactive,
             .unreadable:
            true
        case .active,
             nil:
            false
        }
    }
}

// MARK: Errors

enum PushNotificationsHandlerErrors: Error, Hashable {
    case noContact(String)
}
