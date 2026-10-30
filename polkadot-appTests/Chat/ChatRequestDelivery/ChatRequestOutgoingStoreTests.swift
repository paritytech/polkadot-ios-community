import CoreData
import Foundation
import MessageExchangeKit
import Operation_iOS
import StatementDelivery
import StructuredConcurrency
import Testing
@testable import polkadot_app

struct ChatRequestOutgoingStoreTests {
    private let requestId = "request"
    private let facade = UserDataStorageTestFacade()

    @Test func awaitsFirstDeliveryWhileOutgoingUnsentAndLinkedToContact() async throws {
        try await insertRequest()

        #expect(try await makeStore().isAwaitingFirstDelivery(input(requestId)))
    }

    @Test func doesNotAwaitFirstDeliveryOnceContactPointsElsewhere() async throws {
        try await insertRequest(linkedToContact: false)

        #expect(try await !makeStore().isAwaitingFirstDelivery(input(requestId)))
    }

    @Test func doesNotAwaitFirstDeliveryOfUnknownRequest() async throws {
        #expect(try await !makeStore().isAwaitingFirstDelivery(input(requestId)))
    }

    @Test func firstPublicationSendsWelcomeMessageAndRecordsPeriod() async throws {
        try await insertRequest()
        let store = makeStore()

        let publication = try await store.markPublished(input(requestId), period: 20_000)

        let (period, status) = try await readBack()
        #expect(publication == StatementPublication(period: 20_000, isFirst: true))
        #expect(period == 20_000)
        #expect(status == Chat.LocalMessage.Status.outgoing(.sent).rawValue)
        #expect(try await !store.isAwaitingFirstDelivery(input(requestId)))
    }

    @Test func renewedPublicationOnlyUpdatesPeriod() async throws {
        try await insertRequest()
        let store = makeStore()
        _ = try await store.markPublished(input(requestId), period: 99)

        let publication = try await store.markPublished(input(requestId), period: 100)

        #expect(publication == StatementPublication(period: 100, isFirst: false))
        #expect(try await readBack().period == 100)
    }

    @Test func keepsPeriodAboveInt32Range() async throws {
        try await insertRequest()

        _ = try await makeStore().markPublished(input(requestId), period: UInt32.max)

        #expect(try await readBack().period == UInt32.max)
    }

    @Test func markFailedEndsDeliveryAndDropsPeriod() async throws {
        try await insertRequest()
        let store = makeStore()
        _ = try await store.markPublished(input(requestId), period: 99)

        try await store.markFailed(input(requestId), failure: .terminal(ChatSigningConsentError.declined))

        let (period, status) = try await readBack()
        #expect(status == Chat.LocalMessage.Status.outgoing(.failed).rawValue)
        #expect(period == nil)
    }

    @Test func requestNoLongerLinkedToContactIsAcknowledged() async throws {
        try await insertRequest(linkedToContact: false)

        #expect(try await makeStore().isAcknowledged(input(requestId)))
    }

    @Test func renewalCandidatesAreDeliveredPendingRequestsNewestFirst() async throws {
        let store = makeStore()
        try await recordRequest("older", peer: 1, timestamp: 1)
        try await recordRequest("newer", peer: 2, timestamp: 2)
        try await recordRequest("pending", peer: 3, timestamp: 3)
        _ = try await store.markPublished(input("older"), period: 99)
        _ = try await store.markPublished(input("newer"), period: 100)

        let candidates = try await store.renewalCandidates()

        #expect(candidates.map(\.input.statementId) == ["newer", "older"])
        #expect(candidates.map(\.period) == [100, 99])
        #expect(candidates.first?.input.session.peer.accountId == Data(repeating: 2, count: 32))
    }

    @Test func cancellingRequestIsNotAcknowledged() async throws {
        try await insertRequest(
            status: Chat.RequestStatus.outgoing(.cancelling).rawValue,
            messageStatus: Chat.LocalMessage.Status.outgoing(.sent).rawValue,
            period: 20_000
        )

        #expect(try await !makeStore().isAcknowledged(input(requestId)))
    }

    @Test func cancellingRequestIsNotAwaitingFirstDelivery() async throws {
        try await insertRequest(status: Chat.RequestStatus.outgoing(.cancelling).rawValue)

        #expect(try await !makeStore().isAwaitingFirstDelivery(input(requestId)))
    }

    @Test func cancellingRequestIsNotRenewedButStaysPendingForCancel() async throws {
        let store = makeStore()
        try await recordRequest(requestId, peer: 9, timestamp: 1)
        _ = try await store.markPublished(input(requestId), period: 20_000)
        try await facade.databaseService.performWrite { [requestId] context in
            _ = try context.transitionOutgoingRequest(requestId, from: .pending, to: .cancelling)
        }

        #expect(try await store.renewalCandidates().isEmpty)
        #expect(try await store.pendingRequest(requestId: requestId)?.period == 20_000)
    }
}

private extension ChatRequestOutgoingStoreTests {
    func makeStore() -> ChatRequestOutgoingStore {
        ChatRequestOutgoingStore(storageFacade: facade)
    }

    func input(_ id: String) -> OutgoingChatRequestInput {
        OutgoingChatRequestInput(
            message: Chat.RequestMessage(
                messageId: id,
                timestamp: 1,
                content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
            ),
            session: MessageExchange.SessionRequest(
                own: .init(signKeyId: "//wallet//main", encryptionKeyId: "main", pin: nil),
                peer: .init(accountId: Data(repeating: 9, count: 32), publicKey: Data(), pin: nil, devices: [])
            )
        )
    }

    func insertRequest(
        linkedToContact: Bool = true,
        status: Int16 = Chat.RequestStatus.outgoing(.pending).rawValue,
        messageStatus: Int16 = Chat.LocalMessage.Status.outgoing(.new).rawValue,
        period: UInt32? = nil
    ) async throws {
        try await facade.databaseService.performWrite { [requestId] context in
            let contact = CDChatContact(context: context)
            contact.username = "peer"
            contact.publicKey = Data(repeating: 1, count: 32)

            let message = CDChatMessage(context: context)
            message.messageId = requestId
            message.status = messageStatus

            let request = CDChatRequest(context: context)
            request.identifier = requestId
            request.status = status
            request.message = message
            request.contact = linkedToContact ? contact : nil

            if let period {
                try context.setOutgoingStatementPeriod(period, for: requestId)
            }
        }
    }

    func readBack() async throws -> (period: UInt32?, status: Int16?) {
        try await facade.databaseService.performRead { [requestId] context in
            let fetchRequest = CDChatRequest.fetchRequest()
            fetchRequest.predicate = .chatRequestById(requestId)
            let request = try context.fetch(fetchRequest).first

            return try (context.outgoingStatementPeriod(for: requestId), request?.message?.status)
        }
    }

    func recordRequest(_ requestId: String, peer: UInt8, timestamp: UInt64) async throws {
        let newOutgoing = try ChatRequest.NewOutgoing(
            message: Chat.RequestMessage(
                messageId: requestId,
                timestamp: timestamp,
                content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
            ),
            remoteContact: Chat.RemoteContact(
                accountId: Data(repeating: peer, count: 32),
                username: "peer\(peer)",
                chatPublicKey: Chat.PublicKey(rawData: Data(repeating: peer, count: 32)),
                imageData: nil
            ),
            pushId: nil,
            ownKeyId: Chat.Contact.Own(signKeyId: "//wallet//main", encryptionKeyId: "main")
        )

        try await facade.createRepository(mapper: AnyCoreDataMapper(NewOutgoingChatRequestMapper()))
            .saveOperation({ [newOutgoing] }, { [] })
            .asyncExecute()
    }
}
