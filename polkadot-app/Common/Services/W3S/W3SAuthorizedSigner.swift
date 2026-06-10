import Foundation
import SubstrateSdk
import NovaCrypto
import Individuality

enum W3SAuthorizedSignerError: Error {
    case noSeedFound
}

final class W3SAuthorizedSigner: AuthorizeValueSigning {
    let logger: LoggerProtocol? = Logger.shared
}

extension W3SAuthorizedSigner {
    func canSign() -> Bool {
        fetchSeed() != nil
    }

    func sign(_ data: Data) throws -> Data {
        guard let seed = fetchSeed() else {
            throw W3SAuthorizedSignerError.noSeedFound
        }

        let keypairFactory = Ed25519KeypairFactory()
        let keypair = try keypairFactory.createKeypairFromSeed(
            seed,
            chaincodeList: []
        )

        let signer = EDSigner(privateKey: keypair.privateKey())

        return try signer.sign(data).rawData()
    }
}

private extension W3SAuthorizedSigner {
    func fetchSeed() -> Data? {
        let seedHex = CIKeys.w3sAuthKeyHex

        guard !seedHex.isEmpty else {
            logger?.error("No w3sAuthKey")
            return nil
        }

        return try? seedHex.fromHex()
    }
}
