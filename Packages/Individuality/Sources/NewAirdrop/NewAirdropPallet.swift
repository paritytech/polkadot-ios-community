import Foundation
import BigInt
import SubstrateSdk

public enum NewAirdropPallet {
    public static let name = "Airdrop"

    public typealias EventId = Data
    public typealias AssetId = UInt32
    public typealias AssetBalance = BigUInt
    public typealias Permill = UInt32
    public typealias Slot = Data

    static let gameEventIdBase = Data("pop:game:airdrop:           ".utf8)

    static let airdropContextBase = Data("pop:polkadot.network/airdrop".utf8)

    public static func gameEventId(forGameIndex gameIndex: UInt32) -> EventId {
        gameEventIdBase + withUnsafeBytes(of: gameIndex.bigEndian) { Data($0) }
    }

    public static func airdropContext(forGameIndex gameIndex: UInt32) throws -> Data {
        try (airdropContextBase + gameEventId(forGameIndex: gameIndex)).blake2b32()
    }
}
