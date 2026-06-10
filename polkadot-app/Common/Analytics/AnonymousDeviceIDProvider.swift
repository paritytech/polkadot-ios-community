import Foundation
import KeyDerivation
import Keystore_iOS

protocol AnonymousDeviceIDProviding {
    func getOrCreate() -> String
}

final class AnonymousDeviceIDProvider: AnonymousDeviceIDProviding {
    private let keychain: KeystoreProtocol
    private let generateUUID: () -> UUID

    init(
        keychain: KeystoreProtocol = Keychain(),
        generateUUID: @escaping () -> UUID = UUID.init
    ) {
        self.keychain = keychain
        self.generateUUID = generateUUID
    }

    func getOrCreate() -> String {
        if let existing = read() {
            return existing
        }

        let newID = generateUUID().uuidString
        save(newID)
        return newID
    }

    private func read() -> String? {
        guard let data = try? keychain.fetchKey(for: KeystoreTag.anonymousDeviceIDTag),
              let id = String(data: data, encoding: .utf8) else {
            return nil
        }

        return id
    }

    private func save(_ id: String) {
        try? keychain.saveKey(Data(id.utf8), with: KeystoreTag.anonymousDeviceIDTag)
    }
}
