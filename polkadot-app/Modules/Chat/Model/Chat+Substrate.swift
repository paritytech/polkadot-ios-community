import Foundation
import SubstrateSdk
import Individuality

extension Chat.RemoteContact {
    enum RemoteError: Error {
        case invalidUsername
    }

    init(consumer: ResourcesPallet.ConsumerWithAccountId) throws {
        let chatPublicKey = try Chat.PublicKey(rawData: consumer.info.identifierKey)

        let username = try String(data: consumer.info.username, encoding: .utf8).mapOrThrow(
            RemoteError.invalidUsername
        )

        self.init(
            accountId: consumer.accountId,
            username: username,
            chatPublicKey: chatPublicKey,
            imageData: nil,
            source: .chat
        )
    }
}
