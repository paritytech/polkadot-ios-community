import Foundation
import FoundationExt
import StatementStore
import SubstrateSdk

/// The consent prompt can only be answered in the foreground; not terminal, so the statement is retried later.
struct ChatSigningConsentUnavailableError: Error {}

/// Asks for consent only in the foreground. In the background (a BG task run) it signs with the identity account only
/// when the user already consented, instead of waiting for an alert nobody can see.
final class ForegroundConsentSigningFallback: @unchecked Sendable {
    private let base: NonPrivateSigningFallbacking
    private let activity: any ApplicationActivityProviding

    init(base: NonPrivateSigningFallbacking, activity: any ApplicationActivityProviding) {
        self.base = base
        self.activity = activity
    }
}

extension ForegroundConsentSigningFallback: NonPrivateSigningFallbacking {
    func identitySigner(for contactAccountId: AccountId, ownSignKeyId: String) async throws -> StatementStoreSigning {
        guard await activity.isInBackground else {
            return try await base.identitySigner(for: contactAccountId, ownSignKeyId: ownSignKeyId)
        }

        guard let signer = try await base.consentedIdentitySigner(for: contactAccountId, ownSignKeyId: ownSignKeyId)
        else {
            throw ChatSigningConsentUnavailableError()
        }

        return signer
    }

    func consentedIdentitySigner(for contactAccountId: AccountId, ownSignKeyId: String) async throws
        -> StatementStoreSigning? {
        try await base.consentedIdentitySigner(for: contactAccountId, ownSignKeyId: ownSignKeyId)
    }
}
