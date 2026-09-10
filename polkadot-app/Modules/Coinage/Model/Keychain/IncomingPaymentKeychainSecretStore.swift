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
        let data = try JSONEncoder().encode(StoredDescriptor(descriptor: descriptor))
        try keychain.saveKey(data, with: identifier(for: groupId))
    }

    func fetch(groupId: CoinageTxGroupId) -> IncomingPaymentSourceDescriptor? {
        guard let data = try? keychain.fetchKey(for: identifier(for: groupId)),
              let stored = try? JSONDecoder().decode(StoredDescriptor.self, from: data)
        else {
            return nil
        }
        return stored.descriptor
    }

    func remove(groupId: CoinageTxGroupId) {
        try? keychain.deleteKeyIfExists(for: identifier(for: groupId))
    }

    private func identifier(for groupId: CoinageTxGroupId) -> String {
        Self.keyPrefix + groupId
    }
}

/// The descriptor as tag + hex bytes — a keypair or coin keypairs are rebuilt from these on each run.
private struct StoredDescriptor: Codable {
    let tag: String
    let hex: String?
    let listHex: [String]?

    init(descriptor: IncomingPaymentSourceDescriptor) {
        switch descriptor {
        case let .productAccount(indexData):
            tag = IncomingPaymentSourceKind.productAccount.rawValue
            hex = indexData.toHex()
            listHex = nil
        case let .privateKey(secretKey):
            tag = IncomingPaymentSourceKind.privateKey.rawValue
            hex = secretKey.toHex()
            listHex = nil
        case let .coins(secretKeys):
            tag = IncomingPaymentSourceKind.coins.rawValue
            hex = nil
            listHex = secretKeys.map { $0.toHex() }
        }
    }

    var descriptor: IncomingPaymentSourceDescriptor? {
        switch IncomingPaymentSourceKind(rawValue: tag) {
        case .productAccount:
            (try? hex.map { try Data(hexString: $0) } ?? nil).map { .productAccount(indexData: $0) }
        case .privateKey:
            (try? hex.map { try Data(hexString: $0) } ?? nil).map { .privateKey(secretKey: $0) }
        case .coins:
            listHex.map { .coins(secretKeys: $0.compactMap { try? Data(hexString: $0) }) }
        case .none:
            nil
        }
    }
}
