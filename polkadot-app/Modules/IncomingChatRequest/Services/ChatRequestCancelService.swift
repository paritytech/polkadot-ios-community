import Foundation
import MessageExchangeKit
import StatementDelivery
import StatementStore

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
    let builder: any OutgoingStatementBuilding<OutgoingChatRequestInput>
    let signerManager: StatementStoreSignerManaging
    let consentStore: ChatSigningConsentStoring
    let connection: StatementStoreSubmitting
    let removalCleanup: ChatRemovalCleanupServicing
    let requestStore: ChatRequestStoreServicing
}

/// Publishes a cancel to the peer for every key that may hold a copy of the pending request, then removes it locally.
final class ChatRequestCancelService {
    private let dependencies: ChatRequestCancelDependencies
    private let clock: any Clock<Duration>
    private let submitter: SigningStatementSubmitter

    init(dependencies: ChatRequestCancelDependencies, clock: any Clock<Duration>) {
        self.dependencies = dependencies
        self.clock = clock
        submitter = SigningStatementSubmitter(connection: dependencies.connection)
    }
}

extension ChatRequestCancelService: ChatRequestCancelServicing {
    func cancel(requestId: String) async throws {
        await dependencies.delivery.retire(requestId)

        let pending: PendingOutgoingRequest
        do {
            pending = try await publishCancelOfPendingRequest(requestId: requestId)
        } catch {
            await dependencies.delivery.reinstate(requestId)
            throw error
        }

        try await dependencies.requestStore.deleteOutgoingRequest(requestId)
        try await dependencies.removalCleanup.cleanUpAfterRemoval(of: pending.input.session.peer.accountId)
    }
}

private extension ChatRequestCancelService {
    // Read after retire: a renewal that finished during the wait has already moved the period.
    func publishCancelOfPendingRequest(requestId: String) async throws -> PendingOutgoingRequest {
        guard let pending = try await dependencies.loader.pendingRequest(requestId: requestId) else {
            throw ChatRequestCancelError.notPending
        }

        try await publishCancel(for: pending)

        return pending
    }

    func publishCancel(for pending: PendingOutgoingRequest) async throws {
        guard let period = pending.period else { return }

        let cancel = try makeCancelInput(from: pending.input)

        let oneShotSigner = try dependencies.signerManager.makeSigner(for: cancel.oneShotKeyId(period: period))
        try await submitSkippingNoAllowance(cancel, signer: oneShotSigner)

        guard try await dependencies.consentStore.hasConsent(for: cancel.session.peer.accountId) else { return }

        let identitySigner = try dependencies.signerManager.makeSigner(for: cancel.identitySignKeyId)
        try await submit(cancel, signer: identitySigner)
    }

    func makeCancelInput(from request: OutgoingChatRequestInput) throws -> OutgoingChatRequestInput {
        let identityProof = try dependencies.requestStore.makeOutgoingIdentityProof(
            peerEncryptionPubKey: request.session.peer.publicKey,
            ownEncryptionKeyId: request.session.own.encryptionKeyId
        )

        let cancelMessage = Chat.RequestMessage(
            messageId: request.message.messageId,
            timestamp: Date().toChatTimestamp(),
            content: .cancel(Chat.RequestContentCancel(identityProof: identityProof))
        )

        return OutgoingChatRequestInput(message: cancelMessage, session: request.session)
    }

    // A signer without allowance has no copy to replace, so its publish is skipped.
    func submitSkippingNoAllowance(_ input: OutgoingChatRequestInput, signer: StatementStoreSigning) async throws {
        do {
            try await submit(input, signer: signer)
        } catch StatementSubmitError.rejected(.some(.noAllowance)) {
            return
        }
    }

    // The expiry is rebuilt on retry, so the resubmitted statement carries a fresh priority.
    func submit(_ input: OutgoingChatRequestInput, signer: StatementStoreSigning) async throws {
        do {
            try await submitOnce(input, signer: signer)
        } catch StatementSubmitError.rejected(.some(.channelPriorityTooLow)) {
            try await clock.sleep(for: .seconds(1))
            try await submitOnce(input, signer: signer)
        }
    }

    func submitOnce(_ input: OutgoingChatRequestInput, signer: StatementStoreSigning) async throws {
        try await submitter.submit(dependencies.builder.makeUnsignedStatement(for: input), signer: signer)
    }
}
