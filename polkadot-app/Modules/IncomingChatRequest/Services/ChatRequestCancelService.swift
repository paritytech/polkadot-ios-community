import BackgroundExecution
import Foundation
import Individuality
import MessageExchangeKit
import StatementDelivery
import StatementStore
import SubstrateSdk

protocol ChatRequestCancelServicing {
    func cancel(requestId: String) async throws
}

enum ChatRequestCancelError: Error {
    case notPending
}

struct PendingOutgoingRequest {
    let input: OutgoingChatRequestInput
    /// Nil when the request was never published.
    let period: UInt32?
}

protocol PendingOutgoingChatRequestLoading {
    func pendingRequest(requestId: String) async throws -> PendingOutgoingRequest?
}

struct ChatRequestCancelDependencies {
    let loader: PendingOutgoingChatRequestLoading
    let delivery: any OutgoingStatementDelivering<OutgoingChatRequestInput>
    let builder: any ChatRequestStatementBuilding
    let signerManager: StatementStoreSignerManaging
    let allocator: NotificationStatementAccountAllocating
    let consentStore: ChatSigningConsentStoring
    let connection: StatementStoreConnecting
    let priorityFactory: StatementPriorityMaking
    let removalCleanup: ChatRemovalCleanupServicing
    let requestStore: ChatRequestStoreServicing
    let backgroundExecutor: BackgroundExecuting
}

/// Publishes one cancel from the current period's one-shot account, falling back to the identity account when no slot
/// is free and the user consented, then removes the request locally.
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

        let pending: PendingOutgoingRequest
        do {
            pending = try await publishCancelOfPendingRequest(requestId: requestId)
        } catch {
            await restore(requestId: requestId)
            throw error
        }

        try await dependencies.requestStore.deleteOutgoingRequest(requestId)
        try await dependencies.removalCleanup.cleanUpAfterRemoval(of: pending.input.session.peer.accountId)
    }

    // A revert that fails here is recovered by the launch revert.
    func restore(requestId: String) async {
        try? await dependencies.requestStore.revertOutgoingRequestCancelling(requestId)
        await dependencies.delivery.reinstate(requestId)
    }

    // Read after retire: a first publish that finished during the wait must still be cancelled on the wire.
    func publishCancelOfPendingRequest(requestId: String) async throws -> PendingOutgoingRequest {
        guard let pending = try await dependencies.loader.pendingRequest(requestId: requestId) else {
            throw ChatRequestCancelError.notPending
        }

        try await publishCancel(for: pending)

        return pending
    }

    func publishCancel(for pending: PendingOutgoingRequest) async throws {
        guard pending.period != nil else { return }

        let input = try makeCancelInput(from: pending.input)
        let stored = try await fetchStoredStatements(for: input)

        let signer = try await makeCancelSigner(for: input)
        try await submit(input, signer: signer, expiry: expiry(for: signer, among: stored))
    }

    func makeCancelSigner(for input: OutgoingChatRequestInput) async throws -> StatementStoreSigning {
        do {
            return try await makeCurrentPeriodOneShotSigner(for: input)
        } catch NotificationAllocationError.noFreeSlotInPeriod {
            guard try await dependencies.consentStore.hasConsent(for: input.session.peer.accountId) else {
                throw NotificationAllocationError.noFreeSlotInPeriod
            }

            return try dependencies.signerManager.makeSigner(for: input.identitySignKeyId)
        }
    }

    func makeCurrentPeriodOneShotSigner(for input: OutgoingChatRequestInput) async throws -> StatementStoreSigning {
        let period = try await dependencies.allocator.currentPeriod()
        let signer = try dependencies.signerManager.makeSigner(for: input.oneShotKeyId(period: period))
        try await dependencies.allocator.allocate(signer.accountId, timeout: ChatNotificationSlots.allocationTimeout)

        return signer
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

    // Expiry must exceed the signer's own previous copy on the channel, or the store keeps the old one.
    func expiry(for signer: StatementStoreSigning, among statements: [Statement]) -> UInt64 {
        let timestampPriority = dependencies.priorityFactory.makeTimestampPriority()

        let ownExpiries = statements
            .filter { $0.getSenderAccountId() == signer.accountId }
            .compactMap { $0.getExpiry() }

        guard let lastExpiry = ownExpiries.max() else {
            return timestampPriority
        }

        let (next, overflow) = lastExpiry.addingReportingOverflow(1)
        return overflow ? .max : max(next, timestampPriority)
    }

    func submit(_ input: OutgoingChatRequestInput, signer: StatementStoreSigning, expiry: UInt64) async throws {
        let unsigned = try dependencies.builder.makeUnsignedStatement(for: input, expiry: expiry)
        try await submitter.submit(unsigned, signer: signer)
    }
}
