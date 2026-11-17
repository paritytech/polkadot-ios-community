import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import SubstrateSdkExt
import Individuality

/// The storage requests behind each phase of the location pipeline.
extension VoucherLocationService {
    /// Subscribes to `Members[identifier][voucherPubKey]` for every tracked voucher — including those
    /// already in a recycler, so a ring that keeps filling refreshes the voucher's position and member
    /// count. Detects Onboarding -> Included transitions and in-ring member growth.
    func memberRequests(_ vouchers: [Voucher]) throws -> [BatchStorageSubscriptionRequest] {
        vouchers.map { voucher in
            let publicKey = voucher.publicKey
            let collectionId = RecyclerCollectionIdentifier.identifier(instanceId: instanceId, for: voucher.exponent)
            let mappingKey = SubscriptionKey.member(publicKey: publicKey).mappingKey

            let innerRequest = DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.members(),
                localKey: "",
                keyParamClosure: {
                    (
                        BytesCodable(wrappedValue: collectionId),
                        BytesCodable(wrappedValue: publicKey)
                    )
                }
            )

            return BatchStorageSubscriptionRequest(innerRequest: innerRequest, mappingKey: mappingKey)
        }
    }

    /// The second-phase batch: the two readings per distinct ring, however many vouchers share it, plus
    /// one alias row per placed voucher that has an alias to read.
    func ringRequests(
        for recyclers: [CoinageKeyIndex: RecyclerKey],
        aliases: [CoinageKeyIndex: Data]
    ) -> [BatchStorageSubscriptionRequest] {
        let rings = Set(recyclers.values)

        return ringStatusRequests(for: rings)
            + unloadedCountRequests(for: rings)
            + aliasRequests(for: recyclers, aliases: aliases)
    }

    func ringStatusRequests(for rings: Set<RecyclerKey>) -> [BatchStorageSubscriptionRequest] {
        rings.map { ring in
            let collectionId = RecyclerCollectionIdentifier.identifier(
                instanceId: instanceId,
                for: ring.exponent
            )

            let innerRequest = DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.ringKeysStatus(),
                localKey: "",
                keyParamClosure: {
                    (
                        BytesCodable(wrappedValue: collectionId),
                        StringCodable(wrappedValue: ring.index)
                    )
                }
            )

            return BatchStorageSubscriptionRequest(
                innerRequest: innerRequest,
                mappingKey: SubscriptionKey.ringStatus(recycler: ring).mappingKey
            )
        }
    }

    /// Subscribes to `RecyclersUnloadedCount` per ring. A plain map whose single key is a tuple, so
    /// it goes through `MapSubscriptionRequest` rather than the n-map path used for
    /// `RecyclerAliasStates`.
    func unloadedCountRequests(for rings: Set<RecyclerKey>) -> [BatchStorageSubscriptionRequest] {
        rings.map { ring in
            let key = RecyclerUnloadedCountKey(
                instanceId: instanceId,
                exponent: ring.exponent,
                ringIndex: ring.index
            )

            let innerRequest = MapSubscriptionRequest(
                storagePath: CoinagePallet.Storage.recyclersUnloadedCount(),
                localKey: "",
                keyParamClosure: { key }
            )

            return BatchStorageSubscriptionRequest(
                innerRequest: innerRequest,
                mappingKey: SubscriptionKey.unloadedCount(recycler: ring).mappingKey
            )
        }
    }

    /// Subscribes to `RecyclerAliasStates` per placed voucher. The key carries the ring index, which is
    /// why the alias can only be read once the position is known.
    func aliasRequests(
        for recyclers: [CoinageKeyIndex: RecyclerKey],
        aliases: [CoinageKeyIndex: Data]
    ) -> [BatchStorageSubscriptionRequest] {
        recyclers.compactMap { index, ring in
            guard let alias = aliases[index] else { return nil }

            let key = RecyclerAliasStateKey(
                instanceId: instanceId,
                exponent: ring.exponent,
                ringIndex: ring.index,
                publicKey: alias
            )

            let innerRequest = NMapSubscriptionRequest(
                storagePath: CoinagePallet.Storage.recyclerAliasStates(),
                localKey: "",
                keyParamClosure: { key }
            )

            return BatchStorageSubscriptionRequest(
                innerRequest: innerRequest,
                mappingKey: SubscriptionKey.alias(index: index).mappingKey
            )
        }
    }
}
