import Coinage
import Foundation
import Keystore_iOS
import SubstrateSdk

/// Keychain-backed ``IncomingPaymentSecretStoring`` — the encrypted store for a top-up's source
/// material, the iOS counterpart of Android's encrypted preferences. One entry per operation, keyed
/// by `groupId`, removed the moment a verdict is reached.
final class IncomingPaymentKeychainSecretStore: IncomingPaymentSecretStoring, @unchecked Sendable {
    private static let keyPrefix = "topUpSource."

    private let keychain: KeystoreProtocol

    init(keychain: KeystoreProtocol = Keychain()) {
        self.keychain = keychain
    }

    func save(groupId: CoinageTxGroupId, descriptor: IncomingPaymentSourceDescriptor) throws {
        let data = try JSONEncoder().encode(descriptor)
        try keychain.saveKey(data, with: identifier(for: groupId))
    }

    func fetch(groupId: CoinageTxGroupId) -> IncomingPaymentSourceDescriptor? {
        guard let data = try? keychain.fetchKey(for: identifier(for: groupId)),
              let stored = try? JSONDecoder().decode(IncomingPaymentSourceDescriptor.self, from: data)
        else {
            return nil
        }

        return stored
    }

    func remove(groupId: CoinageTxGroupId) {
        try? keychain.deleteKeyIfExists(for: identifier(for: groupId))
    }

    private func identifier(for groupId: CoinageTxGroupId) -> String {
        Self.keyPrefix + groupId
    }
}
