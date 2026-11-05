import CoreData
import Foundation
@testable import polkadot_app
import SubstrateSdk
import Testing

struct OutgoingChatRequestStatusTests {
    private let facade = UserDataStorageTestFacade()
    private let requestId = "request"

    @Test func cancellingRawValueRoundTrips() {
        #expect(Chat.RequestStatus(rawValue: 7) == .outgoing(.cancelling))
        #expect(Chat.RequestStatus.outgoing(.cancelling).rawValue == 7)
        #expect(Chat.RequestStatus.outgoing(.pending).rawValue == 5)
    }

    @Test func transitionsPendingToCancelling() async throws {
        try await insertRequest(requestId, peer: 1, status: .outgoing(.pending))

        let transitioned = try await facade.databaseService.performWrite { [requestId] context in
            try context.transitionOutgoingRequest(requestId, from: .pending, to: .cancelling)
        }

        #expect(transitioned)
        #expect(try await storedStatus(of: requestId) == .outgoing(.cancelling))
    }

    @Test func transitionFromCancellingFailsWhenStoredPending() async throws {
        try await insertRequest(requestId, peer: 1, status: .outgoing(.pending))

        let transitioned = try await facade.databaseService.performWrite { [requestId] context in
            try context.transitionOutgoingRequest(requestId, from: .cancelling, to: .pending)
        }

        #expect(!transitioned)
        #expect(try await storedStatus(of: requestId) == .outgoing(.pending))
    }

    @Test func revertCancellingRestoresOnlyCancellingRequests() async throws {
        try await insertRequest("cancelling", peer: 1, status: .outgoing(.cancelling))
        try await insertRequest("incoming", peer: 2, status: .incoming(.new))

        try await facade.databaseService.performWrite { context in
            try context.revertCancellingOutgoingRequests()
        }

        #expect(try await storedStatus(of: "cancelling") == .outgoing(.pending))
        #expect(try await storedStatus(of: "incoming") == .incoming(.new))
    }
}

private extension OutgoingChatRequestStatusTests {
    func insertRequest(_ requestId: String, peer: UInt8, status: Chat.RequestStatus) async throws {
        try await facade.databaseService.performWrite { context in
            let peerAccountId = Data(repeating: peer, count: 32)

            let contact = CDChatContact(context: context)
            contact.identifier = peerAccountId.toHex()
            contact.username = "peer\(peer)"
            contact.publicKey = Data(repeating: 1, count: 32)

            let request = CDChatRequest(context: context)
            request.identifier = requestId
            request.status = status.rawValue
            request.contactId = peerAccountId.toHex()
            request.contact = contact
            contact.chatRequest = request
        }
    }

    func storedStatus(of requestId: String) async throws -> Chat.RequestStatus? {
        try await facade.databaseService.performRead { context in
            let fetchRequest = CDChatRequest.fetchRequest()
            fetchRequest.predicate = .chatRequestById(requestId)

            return try context.fetch(fetchRequest).first.flatMap { Chat.RequestStatus(rawValue: $0.status) }
        }
    }
}
