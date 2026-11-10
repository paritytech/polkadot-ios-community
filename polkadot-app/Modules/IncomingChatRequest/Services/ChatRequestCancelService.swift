import BackgroundExecution
import Foundation
import Individuality
import MessageExchangeKit
import SDKLogger
import StatementDelivery
import StatementStore
import StructuredConcurrency
import SubstrateSdk

protocol ChatRequestCancelServicing {
    func cancel(requestId: String) async throws
}

enum ChatRequestCancelError: Error {
    case notPending
}

protocol PendingOutgoingChatRequestLoading {
    func pendingRequest(requestId: String) async throws -> OutgoingChatRequestInput?
}

struct ChatRequestCancelDependencies {
    let loader: PendingOutgoingChatRequestLoading
    let delivery: any OutgoingStatementDelivering<OutgoingChatRequestInput>
    let builder: any ChatRequestStatementBuilding
    let signerManager: StatementStoreSignerManaging
    let periodProvider: NotificationParametersProviding
    let connection: StatementStoreConnecting
    let priorityFactory: StatementPriorityMaking
    let removalCleanup: ChatRemovalCleanupServicing
    let requestStore: ChatRequestStoreServicing
    let backgroundExecutor: BackgroundExecuting
    let logger: SDKLoggerProtocol
    let clock: any Clock<Duration>
}

private struct OwnRequestCopy {
    let statement: Statement
    let signer: StatementStoreSigning
}

private enum CancelRetry {
    static let maxAttempts = 3
    static let firstDelay: Duration = .seconds(1)
}

/// Publishes one cancel per live copy of the request, each signed by the copy's own account, then removes the request
/// locally. A copy the store already dropped for no allowance counts as done.
final class ChatRequestCancelService {
    private let dependencies: ChatRequestCancelDependencies
    private let submitter: SigningStatementSubmitter

    init(dependencies: ChatRequestCancelDependencies) {
        self.dependencies = dependencies
        submitter = SigningStatementSubmitter(connection: dependencies.connection)
    }
}

extension ChatRequestCancelService: ChatRequestCancelServicing {
    func cancel(requestId: String) async throws {
        try await dependencies.requestStore.markOutgoingRequestCancelling(requestId)

        try await dependencies.backgroundExecutor.execute { [self] in
            try await cancelMarkedRequest(requestId: requestId)
        }
    }
}

private extension ChatRequestCancelService {
    func cancelMarkedRequest(requestId: String) async throws {
        await dependencies.delivery.retire(requestId)

        let pending: OutgoingChatRequestInput
        do {
            pending = try await publishCancelOfPendingRequest(requestId: requestId)
        } catch {
            await restore(requestId: requestId)
            throw error
        }

        try await dependencies.requestStore.deleteOutgoingRequest(requestId)
        try await dependencies.removalCleanup.cleanUpAfterRemoval(of: pending.session.peer.accountId)
    }

    // A revert that fails here is recovered by the launch revert.
    func restore(requestId: String) async {
        try? await dependencies.requestStore.revertOutgoingRequestCancelling(requestId)
        await dependencies.delivery.reinstate(requestId)
    }

    // Read after retire: a first publish that finished during the wait must still be cancelled on the wire.
    func publishCancelOfPendingRequest(requestId: String) async throws -> OutgoingChatRequestInput {
        guard let pending = try await dependencies.loader.pendingRequest(requestId: requestId) else {
            throw ChatRequestCancelError.notPending
        }

        try await publishCancel(for: pending)

        return pending
    }

    func publishCancel(for pending: OutgoingChatRequestInput) async throws {
        let input = try makeCancelInput(from: pending)
        let copies = try await fetchOwnCopies(for: input)

        var accepted = false
        var lastFailure: Error?

        for copy in copies {
            do {
                try await withRetry(
                    maxAttempts: CancelRetry.maxAttempts,
                    initialDelay: CancelRetry.firstDelay,
                    clock: dependencies.clock,
                    shouldRetry: { $0.allowsCancelRetry },
                    operation: {
                        try await self.submit(input, signer: copy.signer, expiry: self.expiry(after: copy.statement))
                    }
                )
                accepted = true
            } catch let error as StatementSubmitError where error == .rejected(.noAllowance) {
                // The store drops a copy it rejects for no allowance, so there is nothing left to cancel.
            } catch {
                dependencies.logger.warning("Request cancel failed for one copy: \(error)")
                lastFailure = error
            }
        }

        if let lastFailure, !accepted {
            throw lastFailure
        }
    }

    func fetchOwnCopies(for input: OutgoingChatRequestInput) async throws -> [OwnRequestCopy] {
        let stored = try await fetchStoredStatements(for: input)
        let period = try await dependencies.periodProvider.currentPeriod()
        let signers = try candidateKeyIds(for: input, period: period).map {
            try dependencies.signerManager.makeSigner(for: $0)
        }

        return stored.compactMap { statement in
            guard
                let sender = statement.getSenderAccountId(),
                let signer = signers.first(where: { $0.accountId == sender })
            else {
                dependencies.logger.warning("Skipping a request copy from an unknown account")
                return nil
            }

            return OwnRequestCopy(statement: statement, signer: signer)
        }
    }

    func candidateKeyIds(for input: OutgoingChatRequestInput, period: UInt32) throws -> [String] {
        let currentOneShotKeyId = try input.oneShotKeyId(period: period)
        var keyIds = [input.identitySignKeyId, currentOneShotKeyId]

        if period > 0 {
            try keyIds.append(input.oneShotKeyId(period: period - 1))
        }

        return keyIds
    }

    func makeCancelInput(from request: OutgoingChatRequestInput) throws -> OutgoingChatRequestInput {
        let cancelProof = try dependencies.requestStore.makeOutgoingCancelProof(
            requestId: request.message.messageId,
            peerEncryptionPubKey: request.session.peer.publicKey,
            ownEncryptionKeyId: request.session.own.encryptionKeyId
        )

        let cancelMessage = Chat.RequestMessage(
            messageId: request.message.messageId,
            timestamp: Date().toChatTimestamp(),
            content: .cancel(Chat.RequestContentCancel(identityProof: cancelProof))
        )

        return OutgoingChatRequestInput(message: cancelMessage, session: request.session)
    }

    func fetchStoredStatements(for input: OutgoingChatRequestInput) async throws -> [Statement] {
        let filter = try dependencies.builder.storageTopicFilter(for: input)
        let encoded = try await dependencies.connection.fetchStatements(with: filter)

        return encoded.compactMap { try? Statement(scaleDecoder: ScaleDecoder(data: $0)) }
    }

    // Expiry must exceed the copy's own previous statement on the channel, or the store keeps the old one.
    func expiry(after statement: Statement) -> UInt64 {
        let timestampPriority = dependencies.priorityFactory.makeTimestampPriority()

        guard let copyExpiry = statement.getExpiry() else {
            return timestampPriority
        }

        let (next, overflow) = copyExpiry.addingReportingOverflow(1)
        return overflow ? .max : max(next, timestampPriority)
    }

    func submit(_ input: OutgoingChatRequestInput, signer: StatementStoreSigning, expiry: UInt64) async throws {
        let unsigned = try dependencies.builder.makeUnsignedStatement(for: input, expiry: expiry)
        try await submitter.submit(unsigned, signer: signer)
    }
}

private extension Error {
    var allowsCancelRetry: Bool {
        if let submitError = self as? StatementSubmitError {
            return submitError == .rejected(.channelPriorityTooLow)
        }

        return (self as? JSONRPCOperationError) != .timeout
    }
}
