import StatementStore
@testable import MessageExchangeKit

final class RecordingOutgoingMessageChannel: OutgoingMessageChanneling {
    private(set) var addedMessageBatches: [[TestMessage]] = []

    func activate(restoringState _: [PeerSessionRoute: OutgoingRequest<TestMessage>]) {}

    func deactivate() {}

    func addMessagesToQueue(_ messages: [TestMessage]) {
        addedMessageBatches.append(messages)
    }

    func handleResponse(
        _: MessageExchange.Response,
        route _: PeerSessionRoute
    ) -> StatementHandlingStatus {
        false
    }

    func reset(route _: PeerSessionRoute) {}
}
