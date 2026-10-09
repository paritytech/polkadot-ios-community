import Foundation
import MessageExchangeKit
import os
import StatementStore
import SubstrateSdk
@testable import polkadot_app

final class RecordingOutgoingChatRequestService: OutgoingChatRequestServicing, @unchecked Sendable {
    /// Failures thrown by the leading sends; later sends succeed.
    var failures: [Error] = []
    private(set) var sentSigners: [AccountId] = []

    func send(
        message _: Chat.RequestMessage,
        to _: MessageExchange.Peer,
        ownKeyId _: MessageExchange.Own,
        signer: StatementStoreSigning
    ) async throws {
        if !failures.isEmpty { throw failures.removeFirst() }
        sentSigners.append(signer.accountId)
    }
}

final class StubDeliveryAccountResolver: ChatRequestDeliveryAccountResolving, @unchecked Sendable {
    let signer: ChatRequestDeliverySigner

    init(signer: ChatRequestDeliverySigner) {
        self.signer = signer
    }

    func resolveFirstDelivery(requestId _: String) async throws -> ChatRequestDeliverySigner {
        signer
    }
}

final class InMemoryChatRequestDeliveryStore: ChatRequestDeliveryStoring, @unchecked Sendable {
    var isAwaiting = true
    /// Stops awaiting after this many reads; nil keeps `isAwaiting` as is.
    var awaitingReadsLeft: Int?
    private(set) var delivered: [(requestId: String, anonymousPeriod: UInt32)] = []

    func isAwaitingDelivery(requestId _: String) async throws -> Bool {
        if let left = awaitingReadsLeft {
            awaitingReadsLeft = left - 1
            return left > 0
        }
        return isAwaiting
    }

    func markDelivered(requestId: String, anonymousPeriod: UInt32) async throws {
        delivered.append((requestId, anonymousPeriod))
        isAwaiting = false
    }
}
