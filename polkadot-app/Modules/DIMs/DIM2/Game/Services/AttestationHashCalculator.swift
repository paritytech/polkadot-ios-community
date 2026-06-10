import Foundation
import SubstrateSdk
import Individuality

enum AttestationHashCalculator {
    private static let prefixBytes = Data("polkadot-pop-game".utf8)
    private static let bonusPrefixBytes = Data("dim2-bonus".utf8)

    static func computeBonusHash(
        gameIndex: GamePallet.GameIndex,
        player: GamePallet.AccountOrPerson,
        slot: Int
    ) throws -> Data {
        let prefixEncoder = ScaleEncoder()
        prefixEncoder.appendRaw(data: bonusPrefixBytes)
        let prefixBytesEnc = try prefixEncoder.encode()

        let gameIndexEncoder = ScaleEncoder()
        try gameIndex.encode(scaleEncoder: gameIndexEncoder)
        let gameIndexBytes = try gameIndexEncoder.encode()

        let playerEncoder = ScaleEncoder()
        try player.encode(scaleEncoder: playerEncoder)
        let playerBytes = try playerEncoder.encode()

        let slotEncoder = ScaleEncoder()
        try UInt8(slot).encode(scaleEncoder: slotEncoder)
        let slotBytes = try slotEncoder.encode()

        let fullInput = prefixBytesEnc + gameIndexBytes + playerBytes + slotBytes
        return try fullInput.blake2b32()
    }

    static func computeNftHash(
        gameIndex: GamePallet.GameIndex,
        round: GamePallet.RoundIndex,
        attester: GamePallet.AccountOrPerson,
        attestee: GamePallet.AccountOrPerson
    ) throws -> Data {
        let prefixEncoder = ScaleEncoder()
        prefixEncoder.appendRaw(data: prefixBytes)
        let prefixBytesEnc = try prefixEncoder.encode()

        let gameIndexEncoder = ScaleEncoder()
        try gameIndex.encode(scaleEncoder: gameIndexEncoder)
        let gameIndexBytes = try gameIndexEncoder.encode()

        let roundEncoder = ScaleEncoder()
        try round.encode(scaleEncoder: roundEncoder)
        let roundBytes = try roundEncoder.encode()

        let attesterEncoder = ScaleEncoder()
        try attester.encode(scaleEncoder: attesterEncoder)
        let attesterBytes = try attesterEncoder.encode()

        let attesteeEncoder = ScaleEncoder()
        try attestee.encode(scaleEncoder: attesteeEncoder)
        let attesteeBytes = try attesteeEncoder.encode()

        let fullInput = prefixBytesEnc + gameIndexBytes + roundBytes + attesterBytes + attesteeBytes
        let hash = try fullInput.blake2b32()

        Logger.shared
            .debug(
                "[GameDebug] computeNftHash bytes-in: " +
                    "prefix(\(prefixBytesEnc.count)B)=\(prefixBytesEnc.toHex()) " +
                    "gameIdx(\(gameIndexBytes.count)B)=\(gameIndexBytes.toHex()) " +
                    "round(\(roundBytes.count)B)=\(roundBytes.toHex()) " +
                    "attester(\(attesterBytes.count)B)=\(attesterBytes.toHex()) " +
                    "attestee(\(attesteeBytes.count)B)=\(attesteeBytes.toHex()) " +
                    "totalLen=\(fullInput.count) → hash=\(hash.toHex())"
            )

        return hash
    }
}
