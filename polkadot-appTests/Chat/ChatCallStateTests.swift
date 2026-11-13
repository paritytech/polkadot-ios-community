import Foundation
import Testing

@testable import polkadot_app

@Suite("Chat call state")
struct ChatCallStateTests {
    private typealias MessageContent = Chat.RemoteMessageContentV1.MessageContent

    private let offerId = "offer"
    private let contactId = Data(repeating: 0x01, count: 32)

    @Test("An outgoing call that ends unanswered is cancelled, without a ring duration")
    func outgoingUnansweredIsCancelled() {
        let message = makeOffer(status: .outgoing(.delivered), timestamp: 1_000, related: [
            closed(at: 16_000)
        ])

        #expect(message.resolveCallState() == .cancelled)
    }

    @Test("An incoming call that ends unanswered is missed")
    func incomingUnansweredIsMissed() {
        let message = makeOffer(status: .incoming(.new), timestamp: 1_000, related: [
            closed(at: 16_000)
        ])

        #expect(message.resolveCallState() == .missed)
    }

    @Test("An answered call lasts from the answer to the close, excluding the ringing")
    func answeredCallExcludesRinging() {
        let message = makeOffer(status: .outgoing(.delivered), timestamp: 1_000, related: [
            answer(at: 11_000),
            closed(at: 71_000)
        ])

        #expect(message.resolveCallState() == .finished(durationMs: 60_000))
    }

    @Test("A call still ringing or in progress has no end state")
    func openCalls() {
        let ringing = makeOffer(status: .outgoing(.delivered), timestamp: 1_000, related: [])
        let active = makeOffer(status: .outgoing(.delivered), timestamp: 1_000, related: [answer(at: 5_000)])

        #expect(ringing.resolveCallState() == .calling)
        #expect(active.resolveCallState() == .active)
    }
}

private extension ChatCallStateTests {
    func makeOffer(
        status: Chat.LocalMessage.Status,
        timestamp: Chat.Timestamp,
        related: [Chat.RelatedLocalMessage]
    ) -> Chat.LocalMessage {
        Chat.LocalMessage(
            messageId: offerId,
            chatId: .person(contactId),
            origin: .contact(contactId),
            creationSource: .localDevice,
            status: status,
            timestamp: timestamp,
            content: .call(.offer(MessageContent.DataChannelOfferContent(sdp: Data(), purpose: .audio))),
            reactions: [],
            compactionId: nil,
            relatedMessages: related
        )
    }

    func answer(at timestamp: Chat.Timestamp) -> Chat.RelatedLocalMessage {
        Chat.RelatedLocalMessage(
            messageId: "answer-\(timestamp)",
            timestamp: timestamp,
            content: .call(.answer(MessageContent.DataChannelAnswerContent(offerId: offerId, sdp: Data()))),
            status: .incoming(.new)
        )
    }

    func closed(at timestamp: Chat.Timestamp) -> Chat.RelatedLocalMessage {
        Chat.RelatedLocalMessage(
            messageId: "closed-\(timestamp)",
            timestamp: timestamp,
            content: .call(.closed(MessageContent.DataChannelClosedContent(offerId: offerId))),
            status: .incoming(.new)
        )
    }
}
