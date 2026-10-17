import Foundation
import StatementStore
import SDKLogger

enum PeerSessionPriorityError: Error {
    case expiryExhausted
}

protocol PeerSessionPriorityProviding: AnyObject {
    var expiry: UInt64 { get set }
    /// - Parameter statements: our own authentic statements only; anyone can publish under our topic.
    func initialExpiry(from statements: [Statement]) -> UInt64
    func incrementedExpiry() throws -> UInt64
}

final class PeerSessionPriorityProvider {
    private let priorityFactory: StatementPriorityMaking
    private let logger: SDKLoggerProtocol?

    var expiry: UInt64 = 0

    init(
        priorityFactory: StatementPriorityMaking = StatementPriorityFactory(),
        logger: SDKLoggerProtocol?
    ) {
        self.priorityFactory = priorityFactory
        self.logger = logger
    }
}

extension PeerSessionPriorityProvider: PeerSessionPriorityProviding {
    func initialExpiry(from statements: [Statement]) -> UInt64 {
        let lastUsedPriority = makeExpiry(from: statements)
        let timestampPriority = priorityFactory.makeTimestampPriority()
        let (nextPriority, overflow) = lastUsedPriority.addingReportingOverflow(1)
        return overflow ? .max : max(nextPriority, timestampPriority)
    }

    func incrementedExpiry() throws -> UInt64 {
        let timestampPriority = priorityFactory.makeTimestampPriority()
        let (nextPriority, overflow) = expiry.addingReportingOverflow(1)

        guard !overflow else {
            throw PeerSessionPriorityError.expiryExhausted
        }

        expiry = max(nextPriority, timestampPriority)
        logger?.debug("Incremented expiry: \(expiry)")
        return expiry
    }
}

private extension PeerSessionPriorityProvider {
    func makeExpiry(from statements: [Statement]) -> UInt64 {
        var result = UInt64(0)

        for statement in statements {
            if let expiry = statement.getExpiry(), expiry > result {
                result = expiry
            }
        }

        return result
    }
}
