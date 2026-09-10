import Foundation

/// The encrypted store for a top-up's source material, separate from the record the DB holds.
///
/// Implemented app-side over the Keychain. One entry per operation, keyed by `groupId`, removed the
/// moment a verdict is reached — the keys can only ever build another attempt, and there will not be
/// one. Never enumerated: a descriptor is only ever fetched for a specific unfinished payment.
public protocol IncomingPaymentSecretStoring: Sendable {
    func save(groupId: CoinageTxGroupId, descriptor: IncomingPaymentSourceDescriptor) throws

    /// `nil` only when no secret is stored for `groupId`. A store that cannot be read right now (the
    /// Keychain before first unlock, say) throws instead — the two must stay distinguishable, since
    /// "gone" settles the payment for good.
    func fetch(groupId: CoinageTxGroupId) throws -> IncomingPaymentSourceDescriptor?
    func remove(groupId: CoinageTxGroupId)
}
