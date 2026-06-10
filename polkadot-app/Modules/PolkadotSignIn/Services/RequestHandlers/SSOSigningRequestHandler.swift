import UIKit

protocol SigningRouting: Sendable {
    @MainActor
    func presentSigning(with context: PolkadotSigningContextProtocol) -> UIViewController?
}

final class SSOSigningRequestHandler: SSORequestHandling {
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
        if case .signingRequest = content { return true }
        return false
    }

    func handle(
        message: PolkadotHostRemoteMessage,
        from host: PolkadotSignInHost
    ) async {
        guard case let .signingRequest(value) = message.latestContent() else {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let context = QueuedSsoSigningContext(
                host: host,
                requestMessageId: message.messageId,
                signingModel: .signingRequest(value),
                messageSender: messageSender,
                logger: logger,
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
