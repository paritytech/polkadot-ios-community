import Foundation

extension Chat.LocalMessage {
    func canSendToRemote() -> Bool {
        content.canSendToRemote()
    }

    func toRemote() -> Chat.RemoteMessage? {
        guard
            case .person = chatId,
            let remoteContent = content.toRemote() else {
            return nil
        }

        return Chat.RemoteMessage(
            messageId: messageId,
            timestamp: timestamp,
            versioned: remoteContent
        )
    }

    static func supportsRemote(_ remoteMessage: Chat.RemoteMessage) -> Bool {
        guard let v1Content = remoteMessage.versioned.ensureV1() else {
            return false
        }

        return Chat.LocalMessage.Content.supportsRemoteV1Content(v1Content.content)
    }
}

extension Chat.LocalMessage.Content {
    func canSendToRemote() -> Bool {
        switch self {
        case .text,
             .token,
             .send,
             .coinageSend,
             .contactAdded,
             .leftChat,
             .reacted,
             .reactionRemoved,
             .edited,
             .reply,
             .chatAccepted,
             .multiChatAccepted,
             .deviceAdded,
             .deviceRemoved,
             .call:
            true

        case let .richText(richText):
            richText.isReadyToSend

        case .unsupported,
             .staticTextImageContent,
             .extensionActionResponse,
             .customRendered,
             .file,
             .chatRequest,
             .versionedChatRequest:
            false
        }
    }

    func toRemote() -> Chat.VersionedRemoteMessageContent? {
        guard let v1Content = toRemoteV1Content() else {
            return nil
        }

        return .v1(.init(content: v1Content))
    }
}

private extension Chat.LocalMessage.Content {
    // swiftlint:disable:next cyclomatic_complexity
    func toRemoteV1Content() -> Chat.RemoteMessageContentV1.MessageContent? {
        switch self {
        case let .text(string):
            .text(string)
        case let .token(tokenContent):
            .token(tokenContent)
        case let .send(sendContent):
            .send(sendContent)
        case let .coinageSend(content):
            .coinageSend(.init(totalValue: content.totalValue, coinKeys: content.coinKeys))
        case .contactAdded:
            .contactAdded
        case .leftChat:
            .leftChat
        case let .reacted(reactionContent):
            .reacted(reactionContent)
        case let .reactionRemoved(reactionContent):
            .reactionRemoved(reactionContent)
        case let .edited(editedContent):
            .edited(editedContent)
        case let .reply(replyContent):
            .reply(replyContent)
        case let .chatAccepted(chatAcceptedContent):
            .chatAccepted(chatAcceptedContent)
        case let .richText(richText):
            richText.toRemote().map { ChatRemoteMessageContent.richText($0) }
        case let .call(payload):
            switch payload {
            case let .offer(content):
                .dataChannelOffer(content)
            case let .answer(content):
                .dataChannelAnswer(content)
            case let .candidates(content):
                .dataChannelCandidates(content)
            case let .closed(content):
                .dataChannelClosed(content)
            }
        case .unsupported:
            nil
        case .staticTextImageContent,
             .extensionActionResponse,
             .customRendered,
             .file:
            nil
        case .chatRequest,
             .versionedChatRequest:
            // we are routing it via RequestMessage
            nil
        case let .deviceAdded(content):
            .deviceAdded(content)
        case let .deviceRemoved(content):
            .deviceRemoved(content)
        case let .multiChatAccepted(content):
            .multiChatAccepted(content)
        }
    }

    static func supportsRemoteV1Content(
        _ content: Chat.RemoteMessageContentV1.MessageContent
    ) -> Bool {
        switch content {
        case .text,
             .token,
             .send,
             .coinageSend,
             .contactAdded,
             .leftChat,
             .reply,
             .reacted,
             .reactionRemoved,
             .edited,
             .chatAccepted,
             .multiChatAccepted,
             .richText,
             .deviceAdded,
             .deviceRemoved,
             .dataChannelOffer,
             .dataChannelAnswer,
             .dataChannelCandidates,
             .dataChannelClosed:
            true
        }
    }
}
