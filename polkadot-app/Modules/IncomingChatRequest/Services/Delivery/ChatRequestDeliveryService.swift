import Foundation
import MessageExchangeKit

protocol ChatRequestDelivering: Sendable {
    /// Delivers a recorded outgoing request, retrying with backoff for as long as it still awaits delivery.
    func deliverUntilDone(_ message: Chat.RequestMessage, session: MessageExchange.SessionRequest) async
}

/// First delivery of recorded outgoing chat requests, signed by the account the resolver picks.
final class ChatRequestDeliveryService: @unchecked Sendable {
    private static let firstRetryDelay: Duration = .seconds(2)
    private static let maxRetryDelay: Duration = .seconds(5 * 60)
    private static let maxBackoffDoublings = 8

    private let outgoingService: OutgoingChatRequestServicing
    private let resolver: ChatRequestDeliveryAccountResolving
    private let store: ChatRequestDeliveryStoring
    private let clock: any Clock<Duration>
    private let logger: LoggerProtocol

    init(
        outgoingService: OutgoingChatRequestServicing,
        resolver: ChatRequestDeliveryAccountResolving,
        store: ChatRequestDeliveryStoring,
        clock: any Clock<Duration> = ContinuousClock(),
        logger: LoggerProtocol
    ) {
        self.outgoingService = outgoingService
        self.resolver = resolver
        self.store = store
        self.clock = clock
        self.logger = logger
    }
}

extension ChatRequestDeliveryService: ChatRequestDelivering {
    func deliverUntilDone(_ message: Chat.RequestMessage, session: MessageExchange.SessionRequest) async {
        var attempt = 0

        while await isAwaitingDelivery(message.messageId) {
            do {
                try await deliver(message, session: session)
                logger.debug("Chat request \(message.messageId) delivered after \(attempt + 1) attempt(s)")
                return
            } catch {
                attempt += 1
                let retryIn = Self.retryDelay(forAttempt: attempt)
                logger.error("Chat request \(message.messageId) attempt \(attempt) failed: \(error)")

                do {
                    try await clock.sleep(for: retryIn)
                } catch {
                    return
                }
            }
        }
    }
}

private extension ChatRequestDeliveryService {
    func deliver(_ message: Chat.RequestMessage, session: MessageExchange.SessionRequest) async throws {
        let signer = try await resolver.resolveFirstDelivery(requestId: message.messageId)

        try await outgoingService.send(message: message, to: session.peer, ownKeyId: session.own, signer: signer.signer)
        try await store.markDelivered(requestId: message.messageId, anonymousPeriod: signer.period)
    }

    func isAwaitingDelivery(_ requestId: String) async -> Bool {
        guard !Task.isCancelled else { return false }

        do {
            return try await store.isAwaitingDelivery(requestId: requestId)
        } catch {
            logger.error("Chat request \(requestId) delivery state unreadable: \(error)")
            return false
        }
    }

    static func retryDelay(forAttempt attempt: Int) -> Duration {
        let doublings = min(attempt, maxBackoffDoublings)
        return min(firstRetryDelay * (1 << doublings), maxRetryDelay)
    }
}
