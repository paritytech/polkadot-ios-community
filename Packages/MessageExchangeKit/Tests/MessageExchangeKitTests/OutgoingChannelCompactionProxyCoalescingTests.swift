import Foundation
import Testing
@testable import MessageExchangeKit

struct OutgoingChannelCompactionProxyCoalescingTests {
    private let channel = RecordingOutgoingMessageChannel()
    private let recorder = RecordingOutgoingChannelDelegate()
    private let delegate: AnyOutgoingMessageChannelDelegate<TestMessage>
    private let proxy: OutgoingChannelCompactionProxy<TestMessage>

    init() {
        delegate = AnyOutgoingMessageChannelDelegate(recorder)
        proxy = OutgoingChannelCompactionProxy(
            channel: AnyOutgoingMessageChannel(channel),
            compacter: AnyMessageCompactor(StubMessageCompactor()),
            coalescer: AnyMessageCoalescer(
                StubMessageCoalescer(coalescableIds: [100, 101], fixedDecision: .ignore)
            ),
            routeSelector: PeerSessionRouteSelector { $0.route },
            sizeValidator: FixedSizeValidator(maxPayloadSize: 1_000),
            statementDataCoder: FakeStatementDataCoder(headerSize: 10, messageSize: 10),
            workQueue: DispatchQueue(label: "test.outgoing-channel-compaction-proxy"),
            logger: nil
        )
        proxy.delegate = delegate
    }

    @Test func identicalReceiptIsAcknowledgedWithoutReachingChannel() {
        proxy.activate(restoringState: [:])

        proxy.addMessagesToQueue([TestMessage(id: 100)])
        proxy.addMessagesToQueue([TestMessage(id: 101)])

        #expect(channel.addedMessageBatches.map { $0.map(\.id) } == [[100]])
        #expect(recorder.addToQueueCalls.count == 1)
        #expect(recorder.addToQueueCalls.first?.message.id == 101)
        #expect(recorder.addToQueueCalls.first?.error == nil)
    }
}
