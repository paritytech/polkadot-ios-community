import Foundation
import HandoffService
import SubstrateSdkExt

/// Seals the record under `k_active` with ChaCha20-Poly1305, framed as `nonce || ciphertext || tag`, so only
/// installations that hold the entropy can read it.
struct ActiveInstallationRecordCipher {
    private let encryptor: FileEncrypting

    init(activeKey: Data) {
        encryptor = ChaChaPolyFileEncryptor(rawKey: activeKey)
    }

    func seal(_ installation: ActiveInstallation) throws -> Data {
        try encryptor.encrypt(VersionedActiveDevice.v1(installation).scaleEncoded())
    }

    /// `nil` when the record can't be read: another key or an unknown version.
    func open(_ sealed: Data) -> ActiveInstallation? {
        guard
            let encoded = try? encryptor.decrypt(sealed),
            let record = try? VersionedActiveDevice.fromScaleEncoded(encoded)
        else {
            return nil
        }

        switch record {
        case let .v1(installation):
            return installation
        }
    }
}
