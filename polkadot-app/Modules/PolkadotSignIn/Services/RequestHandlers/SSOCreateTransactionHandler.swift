import UIKit

final class SSOCreateTransactionHandler: SSORequestHandling {
    private let messageSender: PolkadotHostMessageSending
    private let signingHandler: TransactionSigningHandling
    private let logger: LoggerProtocol

    init(
        messageSender: PolkadotHostMessageSending,
        signingHandler: TransactionSigningHandling,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.messageSender = messageSender
        self.signingHandler = signingHandler
        self.logger = logger
    }

    func canHandle(_ content: PolkadotHostRemoteMessage.LatestContent) -> Bool {
        if case .createTransactionRequest = content { return true }
        return false
    }

    func handle(
        message: PolkadotHostRemoteMessage,
        from host: PolkadotSignInHost
    ) async {
        guard case let .createTransactionRequest(value) = message.latestContent() else {
            return
        }

        logger.info("Will start create transaction")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let context = QueuedCreateTransactionContext(
                host: host,
                requestMessageId: message.messageId,
                signingModel: .createTransaction(value.toDomainPayload()),
                messageSender: messageSender,
                onCompleted: { continuation.resume() }
            )

            Task {
                do {
                    try await self.signingHandler.sponsorAndPresent(
                        model: context.signingModel,
                        context: context
                    )
                } catch {
                    self.logger.error("Signing handler failed: \(error)")
                    try? await context.rejectRequest()
                }
            }
        }
    }
}
