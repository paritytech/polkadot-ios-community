import Foundation
import Keystore_iOS
import SubstrateSdk
import KeyDerivation

protocol BackendAuthStoring {
    func fetchAuthWallet() throws -> WalletManaging
}

final class BackendAuthStore: BackendAuthStoring {
    private let keychain: KeystoreProtocol
    private let sessionIdStore: BackendSessionIdStoring
    private let entropyManager: RootEntropyManaging

    init(
        keychain: KeystoreProtocol = Keychain(),
        sessionIdStore: BackendSessionIdStoring = BackendSessionIdStore(),
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) {
        self.keychain = keychain
        self.sessionIdStore = sessionIdStore
        self.entropyManager = entropyManager
    }

    /// The identity the backend sees on `/auth/token`.
    ///
    /// Once a wallet exists this is the main wallet, because the backend only
    /// registers a username for the account that authenticated the request —
    /// it refuses a `candidateAccountId` that is not the authenticated subject
    /// (403, device-uniqueness-backend #77), and the candidate in a claim IS
    /// the main wallet's account.
    ///
    /// Before onboarding creates a wallet there is nothing to authenticate as,
    /// so a random per-session key still backs the pre-wallet calls
    /// (availability checks, attester lookup).
    func fetchAuthWallet() throws -> WalletManaging {
        if (try? entropyManager.hasRootEntropy()) == true {
            return SelectedWallet.main
        }

        let seedBytes = try fetchOrCreateSeedBytes()
        return try DynamicDerivedWallet(seedBytes: seedBytes)
    }
}

private extension BackendAuthStore {
    func fetchOrCreateSeedBytes() throws -> Data {
        let sessionId = sessionIdStore.getOrCreateSessionId()
        let tag = KeystoreTag.backendClientTag(for: sessionId)

        do {
            return try keychain.fetchKey(for: tag)
        } catch KeystoreError.noKeyFound {
            let seedBytes = try Data.randomOrError(of: 32)
            try keychain.saveKey(seedBytes, with: tag)
            return seedBytes
        }
    }
}
