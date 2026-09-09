import Foundation

/// The encrypted store for a top-up's source material, separate from the record the DB holds.
///
/// Implemented app-side over the Keychain. One entry per operation, keyed by `groupId`, removed the
/// moment a verdict is reached — the keys can only ever build another attempt, and there will not be
/// one. Never enumerated: a descriptor is only ever fetched for a specific unfinished payment.
public protocol IncomingPaymentSecretStoring: Sendable {
    func save(groupId: CoinageTxGroupId, descriptor: IncomingPaymentSourceDescriptor) throws
    func fetch(groupId: CoinageTxGroupId) -> IncomingPaymentSourceDescriptor?
    func remove(groupId: CoinageTxGroupId)
}
