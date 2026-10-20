import BigInt
import Foundation
import SubstrateSdk

/// A partial claim is `claimed` with `actualValue` short of the message total; there is no partial status.
struct IncomingTransferState: Equatable, Sendable {
    enum Status: Int16, Sendable {
        case detecting = 0
        case claiming = 1
        case claimed = 2
        case failed = 3

        static let nonTerminalRawValues: [Int16] = [Self.detecting.rawValue, Self.claiming.rawValue]

        var isTerminal: Bool { !Self.nonTerminalRawValues.contains(rawValue) }
    }

    let status: Status
    let actualValue: Balance?

    init(status: Status, actualValue: Balance? = nil) {
        self.status = status
        self.actualValue = actualValue
    }

    var isTerminal: Bool { status.isTerminal }
}

/// A partial claim is `claimed` with `actualValue` short of the message total; there is no partial status.
struct OutgoingTransferState: Equatable, Sendable {
    enum Status: Int16, Sendable {
        case sending = 0
        case sent = 1
        case claimed = 2
        case failed = 3
        case unclaimed = 4

        static let nonTerminalRawValues: [Int16] = [Self.sending.rawValue, Self.sent.rawValue, Self.unclaimed.rawValue]

        var isTerminal: Bool { !Self.nonTerminalRawValues.contains(rawValue) }
    }

    let status: Status
    let actualValue: Balance?

    init(status: Status, actualValue: Balance? = nil) {
        self.status = status
        self.actualValue = actualValue
    }

    var isTerminal: Bool { status.isTerminal }
}
