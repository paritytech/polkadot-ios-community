import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import Individuality

/// Storage key of `Coinage.RecyclerAliasStates`: an n-map keyed by instance, denomination, ring index and
/// the voucher's recycler alias. Shared by the one-shot query and the live location subscription.
struct RecyclerAliasStateKey: NMapKeyStorageKeyProtocol {
    let instanceId: CoinageInstanceId
    let exponent: Int16
    let ringIndex: MembersPallet.RingIndex
    let publicKey: Data

    func appendSubkey(to encoder: any DynamicScaleEncoding, type: String, index: Int) throws {
        switch index {
        case 0:
            try encoder.append(StringCodable(wrappedValue: instanceId), ofType: type)
        case 1:
            try encoder.append(StringCodable(wrappedValue: exponent), ofType: type)
        case 2:
            try encoder.append(StringCodable(wrappedValue: ringIndex), ofType: type)
        case 3:
            try encoder.append(BytesCodable(wrappedValue: publicKey), ofType: type)
        default:
            break
        }
    }
}
