import Foundation
import MessageExchangeKit
import os
import Testing
@testable import polkadot_app

struct IncomingChatAcceptanceCoordinationContextTests {
    private let fixture = ChatAcceptanceFixture()

    @Test func listensOnlyWhileContactsHavePendingOutgoingRequests() async {
        let context = makeContext()
        let listened = OSAllocatedUnfairLock<[[MessageExchange.SessionRequest]]>(initialState: [])
        let builder = { (requests: [MessageExchange.SessionRequest]) -> Task<Void, Never> in
            listened.withLock { $0.append(requests) }
            return Task {}
        }

        await context.update(contacts: [fixture.makeContact()], incomingAcceptanceTaskBuilder: builder)
        await context.update(contacts: [pendingContact()], incomingAcceptanceTaskBuilder: builder)
        await context.update(contacts: [pendingContact()], incomingAcceptanceTaskBuilder: builder)

        #expect(listened.withLock { $0.map(\.count) } == [1])
        #expect(listened.withLock { $0.first?.first?.peer.accountId } == fixture.peerAccountId)
    }

    @Test func acceptanceOfUnknownRequestIsIgnored() async throws {
        let result = try await makeContext().handle(IncomingChatAcceptanceInput(
            peerAccountId: fixture.peerAccountId,
            requestId: "unknown",
            device: Chat.PeerDevice(
                statementAccountId: Data(repeating: 2, count: 32),
                encryptionPublicKey: Data(repeating: 3, count: 32)
            )
        ))

        #expect(result == nil)
    }

    @Test func lateAcceptanceOfCancelledRequestIsIgnored() async throws {
        let cancelled = Chat.Request(
            requestId: "cancelled",
            contactAccountId: fixture.peerAccountId,
            timestamp: 1,
            status: .outgoing(.cancelled),
            message: nil
        )
        let store = MockChatRequestStoreService(localRequests: [cancelled.requestId: cancelled])

        let result = try await makeContext(requestStoreService: store).handle(IncomingChatAcceptanceInput(
            peerAccountId: fixture.peerAccountId,
            requestId: cancelled.requestId,
            device: Chat.PeerDevice(
                statementAccountId: Data(repeating: 2, count: 32),
                encryptionPublicKey: Data(repeating: 3, count: 32)
            )
        ))

        #expect(result == nil)
        #expect(store.calls.isEmpty)
    }
}

private extension IncomingChatAcceptanceCoordinationContextTests {
    func makeContext(
        requestStoreService: ChatRequestStoreServicing? = nil
    ) -> IncomingChatAcceptanceCoordinationContext {
        let facade = UserDataStorageTestFacade()

        return IncomingChatAcceptanceCoordinationContext(
            requestStoreService: requestStoreService ?? ChatRequestStoreService(
                storageFacade: facade,
                pushIdFactory: ChatPushIdFactory(
                    encryptionManager: ChatEncryptionManager(entropyManager: FixedRootEntropyManager()),
                    signManager: ChatSignerManager(entropyManager: FixedRootEntropyManager()),
                    sessionIdFactory: PeerSessionIdFactory(),
                    logger: MockLogger()
                ),
                deviceEncryptionKeyManager: StubDeviceEncryptionKeyManager()
            ),
            contactsStorageService: ContactsLocalStorageService(storageFacade: facade, logger: MockLogger()),
            logger: MockLogger()
        )
    }

    func pendingContact() -> Chat.Contact {
        var contact = fixture.makeContact()
        contact.chatRequest = Chat.Request(
            requestId: "request",
            contactAccountId: fixture.peerAccountId,
            timestamp: 1,
            status: .outgoing(.pending),
            message: nil
        )
        return contact
    }
}
