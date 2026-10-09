import Foundation

enum ChatsComparator {
    static func lastMessageComparator(
        chat1: Chat.LocalModel,
        chat2: Chat.LocalModel
    ) -> Bool {
        guard let message1 = chat1.message, let message2 = chat2.message else {
            return chat1.message != nil ? true : false
        }

        let pair1 = (message1.order, message1.timestamp)
        let pair2 = (message2.order, message2.timestamp)

        guard pair1 != pair2 else {
            return chat1.identifier.localizedCompare(chat2.identifier) == .orderedAscending
        }

        return pair1 > pair2
    }
}
