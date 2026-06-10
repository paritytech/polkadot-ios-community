import Foundation
import Operation_iOS

struct DeviceSyncIncomingMessageFilter {
    let repository: AnyDataProviderRepository<Chat.LocalMessage>
    let logger: LoggerProtocol

    init(
        repository: AnyDataProviderRepository<Chat.LocalMessage>,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.repository = repository
        self.logger = logger
    }

    func filterMessagesToApply(
        in messages: [Chat.LocalMessage]
    ) async throws -> [Chat.LocalMessage] {
        var result: [Chat.LocalMessage] = []
        result.reserveCapacity(messages.count)

        for message in messages {
            let existingMessage = try await repository
                .fetchOperation(by: { message.messageId }, options: .init())
                .asyncExecute()

            guard let existingMessage else {
                result.append(message)
                continue
            }

            guard existingMessage.creationSource == .deviceSync else {
                continue
            }

            if existingMessage.isRequestMessage {
                logger.warning("Skipped synced overwrite for local request message: \(message.messageId)")
                continue
            }

            result.append(message)
        }

        return result
    }
}

private extension Chat.LocalMessage {
    var isRequestMessage: Bool {
        switch content {
        case .chatRequest,
             .versionedChatRequest:
            true
        default:
            false
        }
    }
}
