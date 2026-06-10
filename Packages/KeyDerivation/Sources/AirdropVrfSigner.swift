import Foundation
import NovaCrypto

public struct AirdropVrfSignature {
    public let preOutput: Data
    public let proof: Data
}

public enum AirdropVrfSigner {
    static let label = "pop:airdrop"
    static let eventIdLength = 32

    public static func sign(wallet: RawKeypairProviding, eventId: Data) throws -> AirdropVrfSignature {
        let snPrivateKey = try SNPrivateKey(rawData: wallet.fetchRawSecretKey())
        let snPublicKey = try SNPublicKey(rawData: wallet.getRawPublicKey())
        let snKeypair = SNKeypair(privateKey: snPrivateKey, publicKey: snPublicKey)

        let labelData = Data(label.utf8)
        let domain = labelData + eventId
        let signer = SNVrfSigner(keypair: snKeypair)

        let fields: [SNVrfField] = [
            SNVrfField(key: Data("domain".utf8), value: domain),
            SNVrfField(key: Data("signer".utf8), value: snPublicKey.rawData())
        ]

        let signature = try signer.sign(withLabel: labelData, fields: fields)

        return AirdropVrfSignature(
            preOutput: signature.preOutput,
            proof: signature.proof
        )
    }
}
