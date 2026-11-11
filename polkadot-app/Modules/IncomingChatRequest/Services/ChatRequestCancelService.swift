import BackgroundExecution
import Foundation
import Individuality
import MessageExchangeKit
import SDKLogger
import StatementDelivery
import StatementStore
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
}

private struct OwnRequestCopy {
    let statement: Statement
    let signer: StatementStoreSigning
}

/// Marks the request cancelled and removes its contact and chat at once, then publishes one cancel per live copy,
/// each signed by the copy's own account. Publishing is best effort: a failed cancel is only logged and the store
/// evicts the copy later.
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
        guard let pending = try await dependencies.loader.pendingRequest(requestId: requestId) else {
            throw ChatRequestCancelError.notPending
        }

        try await dependencies.requestStore.markOutgoingRequestCancelled(requestId)
        await cleanUpAfterRemoval(of: pending)

        try await dependencies.backgroundExecutor.execute { [self] in
            await publishCancel(for: pending)
        }
    }
}

private extension ChatRequestCancelService {
    func cleanUpAfterRemoval(of pending: OutgoingChatRequestInput) async {
        do {
            try await dependencies.removalCleanup.cleanUpAfterRemoval(of: pending.session.peer.accountId)
        } catch {
            dependencies.logger.error("Cleanup after request cancel failed: \(error)")
        }
    }

    // Copies are read after retire: a first publish that finished during the wait must still be cancelled.
    func publishCancel(for pending: OutgoingChatRequestInput) async {
        await dependencies.delivery.retire(pending.statementId)

        do {
            let input = try makeCancelInput(from: pending)

            for copy in try await fetchOwnCopies(for: input) {
                await submitCancel(input, replacing: copy)
            }
        } catch {
            dependencies.logger.warning("Request cancel was not published: \(error)")
        }
    }

    func submitCancel(_ input: OutgoingChatRequestInput, replacing copy: OwnRequestCopy) async {
        do {
            let unsigned = try dependencies.builder.makeUnsignedStatement(
                for: input,
                expiry: expiry(after: copy.statement)
            )
            try await submitter.submit(unsigned, signer: copy.signer)
        } catch {
            dependencies.logger.warning("Request cancel failed for one copy: \(error)")
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
}
