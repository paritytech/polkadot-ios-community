import Foundation
import Products

final class SSOAliasRequestHandler: SSORequestHandling {
    private let accountManager: ProductsAccountManaging
    private let messageSender: PolkadotHostMessageSending
    private let logger: LoggerProtocol

    init(
        accountManager: ProductsAccountManaging,
        messageSender: PolkadotHostMessageSending,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.accountManager = accountManager
        self.messageSender = messageSender
        self.logger = logger
    }

    func canHandle(_ content: PolkadotHostRemoteMessage.LatestContent) -> Bool {
        if case .aliasRequest = content { return true }
        return false
    }

    func handle(
        message: PolkadotHostRemoteMessage,
        from host: PolkadotSignInHost
    ) async {
        guard case let .aliasRequest(request) = message.latestContent() else {
            return
        }

        logger.info("Alias request received from \(host.name)")

        let aliasResult: PolkadotHostRemoteMessage.AliasResult

        do {
            let alias = try accountManager.deriveAlias(request.accountId)
            aliasResult = .success(PolkadotHostRemoteMessage.ContextualAlias(
                context: alias.context,
                alias: alias.alias
            ))
        } catch {
            logger.error("Failed to derive alias: \(error)")
            aliasResult = .failure(error.localizedDescription)
        }

        let responseMessage = PolkadotHostRemoteMessage(
            messageId: UUID().uuidString,
            versionedContent: .v1(.aliasResponse(
                requestMessageId: message.messageId,
                result: aliasResult
            ))
        )

        do {
            try await messageSender.postMessage(responseMessage, to: host)
        } catch {
            logger.error("Failed to send alias response: \(error)")
        }
    }
}
