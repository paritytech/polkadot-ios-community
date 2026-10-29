@testable import polkadot_app
import Foundation
import os
import StatementDelivery
import StatementStore

final class RecordingChatRequestStatementBuilder: OutgoingStatementBuilding, @unchecked Sendable {
    private let inputs = OSAllocatedUnfairLock<[OutgoingChatRequestInput]>(initialState: [])

    var builtInputs: [OutgoingChatRequestInput] { inputs.withLock { $0 } }

    func makeUnsignedStatement(for input: OutgoingChatRequestInput) throws -> UnsignedStatement {
        inputs.withLock { $0.append(input) }

        return UnsignedStatement()
    }

    func encodedSize(of _: OutgoingChatRequestInput) throws -> Int {
        0
    }

    func storageTopicFilter(for _: OutgoingChatRequestInput) throws -> TopicFilter {
        .matchAll([])
    }
}
