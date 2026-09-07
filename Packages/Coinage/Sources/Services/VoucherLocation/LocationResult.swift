import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct MemberStatusResult: BatchStorageSubscriptionResult {
    struct MemberUpdate {
        let derivationIndex: DerivationIndex
        let ringPosition: MembersPallet.RingPosition?
    }

    struct RingStatusUpdate {
        let derivationIndex: DerivationIndex
        let ringKeysStatus: MembersPallet.RingKeysStatus?
    }

    /// `RecyclersUnloadedCount` for the ring the voucher sits in. The entry is an `OptionQuery`
    /// populated only as aliases are unloaded, so an absent reading means "none yet", not "unknown".
    struct UnloadedCountUpdate {
        let derivationIndex: DerivationIndex
        let unloadedCount: UInt32?
    }

    let ringPositionUpdates: [MemberUpdate]
    let ringStatusUpdates: [RingStatusUpdate]
    let unloadedCountUpdates: [UnloadedCountUpdate]
    let blockHash: BlockHashData?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        var updates: [MemberUpdate] = []
        var ringStatusUpdates: [RingStatusUpdate] = []
        var unloadedCountUpdates: [UnloadedCountUpdate] = []

        for item in values {
            guard
                let mappingKey = item.mappingKey,
                let subKey = SubscriptionKey(mappingKey: mappingKey)
            else {
                continue
            }

            switch subKey {
            case let .member(derivationIndex):
                let ringPosition = try? item.value.map(
                    to: MembersPallet.RingPosition?.self,
                    with: context
                )

                updates.append(.init(
                    derivationIndex: derivationIndex,
                    ringPosition: ringPosition
                ))

            case let .ringStatus(derivationIndex):
                let ringKeysStatus = try? item.value.map(
                    to: MembersPallet.RingKeysStatus?.self,
                    with: context
                )

                ringStatusUpdates.append(.init(
                    derivationIndex: derivationIndex,
                    ringKeysStatus: ringKeysStatus
                ))

            case let .unloadedCount(derivationIndex):
                let count = try? item.value.map(
                    to: StringScaleMapper<UInt32>?.self,
                    with: context
                )

                unloadedCountUpdates.append(.init(
                    derivationIndex: derivationIndex,
                    unloadedCount: count?.value
                ))
            }
        }

        ringPositionUpdates = updates
        self.ringStatusUpdates = ringStatusUpdates
        self.unloadedCountUpdates = unloadedCountUpdates
        blockHash = try blockHashJson.map(to: BlockHashData?.self, with: context)
    }
}
