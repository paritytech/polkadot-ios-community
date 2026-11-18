import Foundation
import SubstrateSdk

/// Only `.local` slots are ever evicted: the replacement must be signed by the holder.
public enum StatementStoreAllowanceHolder: Equatable, Sendable {
    /// `signerKeyId` is the derivation path of the key this installation holds for the account.
    case local(accountId: AccountId, signerKeyId: String)
    case remote(accountId: AccountId)

    public var accountId: AccountId {
        switch self {
        case let .local(accountId, _),
             let .remote(accountId):
            accountId
        }
    }

    public var signerKeyId: String? {
        switch self {
        case let .local(_, signerKeyId):
            signerKeyId
        case .remote:
            nil
        }
    }
}
