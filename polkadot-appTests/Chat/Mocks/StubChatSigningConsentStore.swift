@testable import polkadot_app
import SubstrateSdk

final class StubChatSigningConsentStore: ChatSigningConsentStoring, @unchecked Sendable {
    private let consented: Bool

    init(consented: Bool) {
        self.consented = consented
    }

    func hasConsent(for _: AccountId) async throws -> Bool {
        consented
    }

    func grant(for _: AccountId) async throws {}

    func revoke(for _: AccountId) async throws {}
}
