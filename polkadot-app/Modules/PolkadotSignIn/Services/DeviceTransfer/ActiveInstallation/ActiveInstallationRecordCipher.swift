import Foundation
import MessageExchangeKit
import SubstrateSdkExt

/// Seals the record under `HKDF-SHA256(k_active)`, so only installations that hold the entropy can read it.
struct ActiveInstallationRecordCipher {
    private let encryptor: RawSecretChaChaPolyEncryptor

    init(activeKey: Data) {
        encryptor = RawSecretChaChaPolyEncryptor(sharedSecret: activeKey)
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
