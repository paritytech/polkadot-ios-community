import Foundation
import SubstrateSdk
import SubstrateStorageSubscription

struct CoinSyncResult: BatchStorageSubscriptionResult {
    let updates: [String: OnChainCoin?]

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson _: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        var parsedUpdates: [String: OnChainCoin?] = [:]

        for value in values {
            guard let mappingKey = value.mappingKey else { continue }

            let coin = try value.value.map(to: OnChainCoin?.self, with: context)
            parsedUpdates[mappingKey] = coin
        }

        updates = parsedUpdates
    }
}

extension CoinSyncResult {
    /// Representation of the Coin struct stored on-chain in CoinagePallet.
    struct OnChainCoin: Codable {
        @StringCodable var instanceId: UInt32
        @StringCodable var value: Int8
        @StringCodable var age: Int16
    }
}

extension CoinSyncResult.OnChainCoin? {
    /// `CoinsByOwner` is keyed by public key alone, so a key can hold a coin of a foreign Coinage instance
    /// (another unit or asset). Such a coin reads as absent.
    func filtered(by instanceId: CoinageInstanceId) -> CoinSyncResult.OnChainCoin? {
        flatMap { $0.instanceId == instanceId ? $0 : nil }
    }
}

extension CoinSyncResult {
    func updates(in instanceId: CoinageInstanceId) -> [String: OnChainCoin?] {
        updates.mapValues { $0.filtered(by: instanceId) }
    }
}
